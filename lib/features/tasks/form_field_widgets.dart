import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/theme.dart';
import '../files/file_repository.dart';

/// Inputs for the task-form field types that need more than a text box.
///
/// The web form builder can author every type the backend's `TaskFormFieldType`
/// defines, but most of them are captures only a phone can do — a GPS reading, a
/// scan, a signature. The web renderer says as much on the field itself
/// ("available on mobile app"), which makes this file the other half of that
/// promise.
///
/// Every widget here stores the same value shape the web renderer writes for the
/// same type, so a form filled on one side reads back on the other and in
/// reports. Where the web offers a manual box as its fallback, the stored value
/// is the string that box would have produced.

// ─────────────────────────── Selection ───────────────────────────

/// Multi-select as a wrap of toggleable chips. Stores `List<String>`.
class TfMultiSelect extends StatelessWidget {
  const TfMultiSelect({
    super.key,
    required this.options,
    required this.value,
    required this.readOnly,
    required this.onChanged,
  });

  final List<String> options;
  final dynamic value;
  final bool readOnly;
  final void Function(dynamic) onChanged;

  List<String> get _selected {
    if (value is List) return (value as List).map((e) => e.toString()).toList();
    if (value is String && (value as String).isNotEmpty) return [value as String];
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          FilterChip(
            label: Text(o),
            selected: selected.contains(o),
            onSelected: readOnly
                ? null
                : (on) {
                    final next = [...selected];
                    on ? next.add(o) : next.remove(o);
                    onChanged(next.isEmpty ? null : next);
                  },
          ),
      ],
    );
  }
}

/// One-of-many as chips — button groups, Likert scales and emoji ratings all
/// pick a single option. Stores the chosen option string.
class TfChoiceChips extends StatelessWidget {
  const TfChoiceChips({
    super.key,
    required this.options,
    required this.value,
    required this.readOnly,
    required this.onChanged,
    this.big = false,
  });

  final List<String> options;
  final dynamic value;
  final bool readOnly;
  final void Function(dynamic) onChanged;

  /// Emoji ratings read better large and unboxed.
  final bool big;

  @override
  Widget build(BuildContext context) {
    final current = value?.toString();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          ChoiceChip(
            label: Text(o, style: TextStyle(fontSize: big ? 22 : 13)),
            selected: current == o,
            onSelected: readOnly ? null : (_) => onChanged(current == o ? null : o),
          ),
      ],
    );
  }
}

/// Yes/no switch. Stores a bool.
class TfToggle extends StatelessWidget {
  const TfToggle({
    super.key,
    required this.value,
    required this.readOnly,
    required this.onChanged,
  });

  final dynamic value;
  final bool readOnly;
  final void Function(dynamic) onChanged;

  @override
  Widget build(BuildContext context) {
    final on = value == true || value == 'true';
    return Row(
      children: [
        Switch(
          value: on,
          onChanged: readOnly ? null : (v) => onChanged(v),
        ),
        const SizedBox(width: 4),
        Text(on ? 'Yes' : 'No',
            style: TextStyle(fontSize: 13, color: AppColors.inkSoft)),
      ],
    );
  }
}

/// Drag-to-order list. Stores the ordered `List<String>`.
class TfRanking extends StatelessWidget {
  const TfRanking({
    super.key,
    required this.options,
    required this.value,
    required this.readOnly,
    required this.onChanged,
  });

  final List<String> options;
  final dynamic value;
  final bool readOnly;
  final void Function(dynamic) onChanged;

  List<String> get _order {
    final stored =
        value is List ? (value as List).map((e) => e.toString()).toList() : <String>[];
    // Anything the builder added after the answer was started goes to the end,
    // and anything it removed is dropped.
    final kept = stored.where(options.contains).toList();
    for (final o in options) {
      if (!kept.contains(o)) kept.add(o);
    }
    return kept;
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: !readOnly,
      onReorder: (from, to) {
        if (readOnly) return;
        final next = [...order];
        if (to > from) to -= 1;
        next.insert(to, next.removeAt(from));
        onChanged(next);
      },
      children: [
        for (var i = 0; i < order.length; i++)
          ListTile(
            key: ValueKey(order[i]),
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: CircleAvatar(
              radius: 12,
              backgroundColor: AppColors.primary.withOpacity(0.12),
              child: Text('${i + 1}',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
            ),
            title: Text(order[i], style: const TextStyle(fontSize: 13.5)),
            trailing: readOnly ? null : const Icon(Icons.drag_handle_rounded, size: 18),
          ),
      ],
    );
  }
}

// ─────────────────────────── Rating ───────────────────────────

/// Tap-a-star rating. Stores an int; `max` defaults to 5.
class TfStarRating extends StatelessWidget {
  const TfStarRating({
    super.key,
    required this.value,
    required this.readOnly,
    required this.onChanged,
    this.max = 5,
  });

  final dynamic value;
  final bool readOnly;
  final void Function(dynamic) onChanged;
  final int max;

  @override
  Widget build(BuildContext context) {
    final current = value is num ? (value as num).toInt() : int.tryParse('$value') ?? 0;
    return Row(
      children: [
        for (var i = 1; i <= max; i++)
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            constraints: const BoxConstraints(),
            icon: Icon(
              i <= current ? Icons.star_rounded : Icons.star_border_rounded,
              size: 30,
              color: i <= current ? AppColors.warning : AppColors.hairline,
            ),
            onPressed: readOnly ? null : () => onChanged(i == current ? null : i),
          ),
        if (current > 0) ...[
          const SizedBox(width: 8),
          Text('$current / $max',
              style: TextStyle(fontSize: 12, color: AppColors.muted)),
        ],
      ],
    );
  }
}

/// Net promoter score, 0–10. Stores an int.
class TfNpsScore extends StatelessWidget {
  const TfNpsScore({
    super.key,
    required this.value,
    required this.readOnly,
    required this.onChanged,
  });

  final dynamic value;
  final bool readOnly;
  final void Function(dynamic) onChanged;

  @override
  Widget build(BuildContext context) {
    final current = value is num ? (value as num).toInt() : int.tryParse('$value');
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i <= 10; i++)
          SizedBox(
            width: 38,
            child: ChoiceChip(
              labelPadding: EdgeInsets.zero,
              label: Center(child: Text('$i', style: const TextStyle(fontSize: 12.5))),
              selected: current == i,
              onSelected:
                  readOnly ? null : (_) => onChanged(current == i ? null : i),
            ),
          ),
      ],
    );
  }
}

/// Slider rating between the field's min and max. Stores a num.
class TfSliderRating extends StatelessWidget {
  const TfSliderRating({
    super.key,
    required this.value,
    required this.readOnly,
    required this.onChanged,
    this.min = 0,
    this.max = 10,
  });

  final dynamic value;
  final bool readOnly;
  final void Function(dynamic) onChanged;
  final double min;
  final double max;

  @override
  Widget build(BuildContext context) {
    final raw = value is num ? (value as num).toDouble() : double.tryParse('$value');
    final current = (raw ?? min).clamp(min, max);
    final divisions = (max - min) >= 1 ? (max - min).round() : null;
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: current.toDouble(),
            min: min,
            max: max,
            divisions: divisions,
            label: current.toStringAsFixed(0),
            onChanged: readOnly ? null : (v) => onChanged(v.round()),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(raw == null ? '—' : current.toStringAsFixed(0),
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

// ─────────────────────────── Approval ───────────────────────────

/// Approve / reject pair. Stores `"APPROVED"` or `"REJECTED"`, matching the web.
class TfApproval extends StatelessWidget {
  const TfApproval({
    super.key,
    required this.value,
    required this.readOnly,
    required this.onChanged,
  });

  final dynamic value;
  final bool readOnly;
  final void Function(dynamic) onChanged;

  @override
  Widget build(BuildContext context) {
    final current = value?.toString();
    Widget button(String key, String label, IconData icon, Color color) {
      final on = current == key;
      return Expanded(
        child: OutlinedButton.icon(
          onPressed: readOnly ? null : () => onChanged(on ? null : key),
          style: OutlinedButton.styleFrom(
            foregroundColor: on ? color : AppColors.inkSoft,
            backgroundColor: on ? color.withOpacity(0.08) : null,
            side: BorderSide(
                color: on ? color : AppColors.hairline, width: on ? 1.4 : 1),
          ),
          icon: Icon(icon, size: 18),
          label: Text(label),
        ),
      );
    }

    return Row(
      children: [
        button('APPROVED', 'Approve', Icons.check_rounded, AppColors.success),
        const SizedBox(width: 10),
        button('REJECTED', 'Reject', Icons.close_rounded, AppColors.danger),
      ],
    );
  }
}

// ─────────────────────────── Signature / drawing ───────────────────────────

/// Finger-drawn signature or sketch, uploaded as a PNG.
///
/// Stores the same uploaded-file descriptor an image field stores, so a
/// signature shows up wherever attachments are listed and needs no special
/// handling on the way out.
class TfSignaturePad extends ConsumerStatefulWidget {
  const TfSignaturePad({
    super.key,
    required this.value,
    required this.readOnly,
    required this.onChanged,
    this.hint = 'Sign above',
  });

  final dynamic value;
  final bool readOnly;
  final void Function(dynamic) onChanged;
  final String hint;

  @override
  ConsumerState<TfSignaturePad> createState() => _TfSignaturePadState();
}

class _TfSignaturePadState extends ConsumerState<TfSignaturePad> {
  final _boundaryKey = GlobalKey();
  final List<List<Offset>> _strokes = [];
  bool _busy = false;

  Map<String, dynamic>? get _stored =>
      widget.value is Map ? Map<String, dynamic>.from(widget.value as Map) : null;

  Future<void> _save() async {
    if (_strokes.isEmpty) return;
    setState(() => _busy = true);
    try {
      final boundary = _boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw 'Could not read the drawing';
      final dir = await getTemporaryDirectory();
      final name = 'signature_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);

      final up = await ref.read(fileRepositoryProvider).upload(file.path, filename: name);
      widget.onChanged(up.toJson());
      if (mounted) setState(() => _strokes.clear());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stored = _stored;

    if (stored != null) {
      return Row(
        children: [
          Icon(Icons.draw_rounded, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(stored['originalName']?.toString() ?? 'Signed',
                style: const TextStyle(fontSize: 13.5)),
          ),
          if (!widget.readOnly)
            TextButton(
              onPressed: () => widget.onChanged(null),
              child: const Text('Redo'),
            ),
        ],
      );
    }

    if (widget.readOnly) {
      return Text('Not signed',
          style: TextStyle(fontSize: 13, color: AppColors.muted));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RepaintBoundary(
          key: _boundaryKey,
          child: Container(
            height: 180,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.hairline),
              borderRadius: BorderRadius.circular(8),
            ),
            child: GestureDetector(
              onPanStart: (d) => setState(() => _strokes.add([d.localPosition])),
              onPanUpdate: (d) => setState(() {
                if (_strokes.isEmpty) _strokes.add([]);
                _strokes.last.add(d.localPosition);
              }),
              child: CustomPaint(
                painter: _StrokePainter(_strokes),
                size: Size.infinite,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(widget.hint,
                style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
            const Spacer(),
            TextButton(
              onPressed:
                  _strokes.isEmpty || _busy ? null : () => setState(_strokes.clear),
              child: const Text('Clear'),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: _strokes.isEmpty || _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }
}

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.strokes);

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      for (var i = 0; i < stroke.length - 1; i++) {
        canvas.drawLine(stroke[i], stroke[i + 1], paint);
      }
      if (stroke.length == 1) {
        canvas.drawPoints(ui.PointMode.points, [stroke.first], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter old) => true;
}

// ─────────────────────────── Scanner ───────────────────────────

/// QR / barcode capture with a manual fallback.
///
/// The manual box is deliberate: a damaged label still has to be recordable, and
/// it keeps the value identical to what the web's manual box writes.
class TfScannerField extends StatefulWidget {
  const TfScannerField({
    super.key,
    required this.value,
    required this.readOnly,
    required this.onChanged,
    required this.label,
    this.canScan = true,
    this.note,
  });

  final dynamic value;
  final bool readOnly;
  final void Function(dynamic) onChanged;
  final String label;

  /// False for NFC, which needs a native reader the app does not ship.
  final bool canScan;
  final String? note;

  @override
  State<TfScannerField> createState() => _TfScannerFieldState();
}

class _TfScannerFieldState extends State<TfScannerField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value?.toString() ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => _ScanSheet(title: widget.label)),
    );
    if (code == null) return;
    _controller.text = code;
    widget.onChanged(code);
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.canScan && !widget.readOnly) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
              label: Text('Scan ${widget.label.toLowerCase()}'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _controller,
          readOnly: widget.readOnly,
          decoration: InputDecoration(
            hintText: widget.canScan ? 'Or enter it manually' : 'Enter the value',
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (s) => widget.onChanged(s.isEmpty ? null : s),
        ),
        if (widget.note != null) ...[
          const SizedBox(height: 4),
          Text(widget.note!,
              style: TextStyle(fontSize: 11, color: AppColors.muted)),
        ],
      ],
    );
  }
}

class _ScanSheet extends StatefulWidget {
  const _ScanSheet({required this.title});

  final String title;

  @override
  State<_ScanSheet> createState() => _ScanSheetState();
}

class _ScanSheetState extends State<_ScanSheet> {
  final _controller =
      MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: MobileScanner(
        controller: _controller,
        onDetect: (capture) {
          if (_done) return;
          final code = capture.barcodes
              .map((b) => b.rawValue)
              .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
          if (code == null) return;
          _done = true;
          Navigator.of(context).pop(code);
        },
      ),
    );
  }
}

// ─────────────────────────── Map point ───────────────────────────

/// Pick a point on a map. Stores `"lat, lng"` — the same string a GPS capture
/// and the web's manual box write.
class TfMapPointField extends StatelessWidget {
  const TfMapPointField({
    super.key,
    required this.value,
    required this.readOnly,
    required this.onChanged,
  });

  final String value;
  final bool readOnly;
  final void Function(dynamic) onChanged;

  static LatLng? parse(String raw) {
    final parts = raw.split(',');
    if (parts.length != 2) return null;
    final lat = double.tryParse(parts[0].trim());
    final lng = double.tryParse(parts[1].trim());
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  @override
  Widget build(BuildContext context) {
    final point = parse(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (point != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 150,
              child: IgnorePointer(
                child: FlutterMap(
                  options: MapOptions(initialCenter: point, initialZoom: 15),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.nava360.app',
                    ),
                    MarkerLayer(markers: [
                      Marker(
                        point: point,
                        width: 40,
                        height: 40,
                        child: Icon(Icons.place_rounded,
                            size: 36, color: AppColors.danger),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        if (point != null) ...[
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 12.5)),
        ],
        if (!readOnly) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final picked = await Navigator.of(context).push<LatLng>(
                  MaterialPageRoute(builder: (_) => _MapPicker(initial: point)),
                );
                if (picked != null) {
                  onChanged('${picked.latitude.toStringAsFixed(6)}, '
                      '${picked.longitude.toStringAsFixed(6)}');
                }
              },
              icon: const Icon(Icons.map_rounded, size: 18),
              label: Text(point == null ? 'Pick on map' : 'Change point'),
            ),
          ),
        ],
        if (point == null && readOnly)
          Text('Not set', style: TextStyle(fontSize: 13, color: AppColors.muted)),
      ],
    );
  }
}

class _MapPicker extends StatefulWidget {
  const _MapPicker({this.initial});

  final LatLng? initial;

  @override
  State<_MapPicker> createState() => _MapPickerState();
}

class _MapPickerState extends State<_MapPicker> {
  final _map = MapController();
  LatLng? _chosen;
  LatLng _center = const LatLng(20.5937, 78.9629); // India, until we know better

  @override
  void initState() {
    super.initState();
    _chosen = widget.initial;
    if (widget.initial != null) {
      _center = widget.initial!;
    } else {
      _locate();
    }
  }

  Future<void> _locate() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) {
        setState(() => _center = LatLng(last.latitude, last.longitude));
        _map.move(_center, 15);
      }
    } catch (_) {
      // Falls back to the default centre; the user can still pan and tap.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tap to place the point'),
        actions: [
          TextButton(
            onPressed: _chosen == null
                ? null
                : () => Navigator.of(context).pop(_chosen),
            child: const Text('Use'),
          ),
        ],
      ),
      body: FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: _center,
          initialZoom: widget.initial == null ? 5 : 15,
          onTap: (_, p) => setState(() => _chosen = p),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.nava360.app',
          ),
          if (_chosen != null)
            MarkerLayer(markers: [
              Marker(
                point: _chosen!,
                width: 44,
                height: 44,
                child: Icon(Icons.place_rounded, size: 40, color: AppColors.danger),
              ),
            ]),
        ],
      ),
    );
  }
}

// ─────────────────────────── Repeatable rows ───────────────────────────

/// A repeatable list of free-text rows, used for `table` and
/// `repeatable_section`. Stores `List<String>`.
///
/// The form schema carries no column definitions — the builder has no way to
/// author them yet — so a row is a single line of text rather than a fabricated
/// set of columns. When the builder grows real columns this is the widget to
/// replace.
class TfRepeatableRows extends StatelessWidget {
  const TfRepeatableRows({
    super.key,
    required this.value,
    required this.readOnly,
    required this.onChanged,
    this.addLabel = 'Add row',
  });

  final dynamic value;
  final bool readOnly;
  final void Function(dynamic) onChanged;
  final String addLabel;

  List<String> get _rows =>
      value is List ? (value as List).map((e) => e.toString()).toList() : <String>[];

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: rows[i],
                    readOnly: readOnly,
                    decoration: InputDecoration(
                      isDense: true,
                      border: const OutlineInputBorder(),
                      prefixText: '${i + 1}.  ',
                    ),
                    onChanged: (s) {
                      final next = [...rows]..[i] = s;
                      onChanged(next);
                    },
                  ),
                ),
                if (!readOnly)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close_rounded, size: 18, color: AppColors.muted),
                    onPressed: () {
                      final next = [...rows]..removeAt(i);
                      onChanged(next.isEmpty ? null : next);
                    },
                  ),
              ],
            ),
          ),
        if (!readOnly)
          TextButton.icon(
            onPressed: () => onChanged([...rows, '']),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(addLabel),
          ),
        if (readOnly && rows.isEmpty)
          Text('Nothing added',
              style: TextStyle(fontSize: 13, color: AppColors.muted)),
      ],
    );
  }
}

/// A value per configured row, used for `matrix`. Stores `Map<String, String>`
/// keyed by the row label so a renamed row never silently inherits an answer.
class TfMatrixField extends StatelessWidget {
  const TfMatrixField({
    super.key,
    required this.rows,
    required this.value,
    required this.readOnly,
    required this.onChanged,
  });

  final List<String> rows;
  final dynamic value;
  final bool readOnly;
  final void Function(dynamic) onChanged;

  Map<String, String> get _answers {
    if (value is Map) {
      return (value as Map)
          .map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
    }
    return {};
  }

  @override
  Widget build(BuildContext context) {
    final answers = _answers;
    if (rows.isEmpty) {
      return Text('No rows configured for this field.',
          style: TextStyle(fontSize: 12, color: AppColors.muted));
    }
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 4,
                  child: Text(row, style: const TextStyle(fontSize: 13)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 5,
                  child: TextFormField(
                    initialValue: answers[row] ?? '',
                    readOnly: readOnly,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (s) {
                      final next = {...answers, row: s};
                      next.removeWhere((_, v) => v.isEmpty);
                      onChanged(next.isEmpty ? null : next);
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────── Layout & system ───────────────────────────

/// Section headers, headings, paragraphs, dividers and spacers: the parts of a
/// form that organise it rather than ask anything.
class TfLayoutBlock extends StatelessWidget {
  const TfLayoutBlock({super.key, required this.kind, required this.label, this.helpText});

  /// One of section / divider / heading / paragraph / spacer.
  final String kind;
  final String label;
  final String? helpText;

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case 'divider':
        return Divider(color: AppColors.hairline, height: 24);
      case 'spacer':
        return const SizedBox(height: 16);
      case 'heading':
        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Text(label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        );
      case 'paragraph':
        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(label,
              style: TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.4)),
        );
      case 'section':
      default:
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.primary.withOpacity(0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
              if (helpText != null && helpText!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(helpText!,
                      style: TextStyle(
                          fontSize: 11.5, color: AppColors.primary.withOpacity(0.8))),
                ),
            ],
          ),
        );
    }
  }
}

/// A value the system supplies — a formula result, a sequence number, the
/// current user or branch, a timestamp. Shown so the user knows it is being
/// recorded, never presented as something to fill in.
class TfAutoFilled extends StatelessWidget {
  const TfAutoFilled({super.key, required this.text, this.mono = false});

  final String text;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded, size: 15, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.inkSoft,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
