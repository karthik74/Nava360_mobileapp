import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/download_saver.dart';
import '../../core/pro_ui.dart';
import '../../core/theme.dart';

const _a4WidthMm = 210.0;
const _a4HeightMm = 297.0;

class _Adj {
  double x = 0; // mm, + right
  double y = 0; // mm, + down
  double zoom = 100; // percent
}

/// Simplified mobile equivalent of the web Letter Head aligner: pick a PDF,
/// nudge each page on an A4 sheet (same model as web: fit-to-A4, centred, then
/// X/Y mm offset + zoom %), and export the aligned A4 PDF (current page or all).
/// Like the web output, the letterhead artwork is NOT embedded - the result is
/// meant to be printed on pre-printed letterhead paper.
class LetterheadAlignScreen extends StatefulWidget {
  const LetterheadAlignScreen({super.key});

  @override
  State<LetterheadAlignScreen> createState() => _LetterheadAlignScreenState();
}

class _LetterheadAlignScreenState extends State<LetterheadAlignScreen> {
  String _fileName = '';
  final List<Uint8List> _pages = []; // PNG per source page
  final List<Size> _sizes = []; // px size per page
  final List<_Adj> _adj = [];
  int _current = 0;
  bool _applyToAll = true;
  bool _allPages = false;
  bool _busy = false;
  String? _error;

  _Adj get _a => _adj[_current];

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    final f = res?.files.single;
    if (f == null) return;
    final bytes = f.bytes;
    if (bytes == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final pages = <Uint8List>[];
      final sizes = <Size>[];
      await for (final p in Printing.raster(bytes, dpi: 130)) {
        pages.add(await p.toPng());
        sizes.add(Size(p.width.toDouble(), p.height.toDouble()));
      }
      if (pages.isEmpty) throw Exception('The PDF has no pages');
      setState(() {
        _fileName = f.name;
        _pages
          ..clear()
          ..addAll(pages);
        _sizes
          ..clear()
          ..addAll(sizes);
        _adj
          ..clear()
          ..addAll(List.generate(pages.length, (_) => _Adj()));
        _current = 0;
      });
    } catch (e) {
      setState(() => _error = 'Could not read that PDF: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _change(void Function(_Adj a) fn) {
    setState(() {
      if (_applyToAll) {
        for (final a in _adj) {
          fn(a);
        }
      } else {
        fn(_a);
      }
    });
  }

  // Geometry of a page on the A4 sheet in mm: returns (left, top, width, height).
  (double, double, double, double) _rect(int i) {
    final s = _sizes[i];
    final fit = (_a4WidthMm / s.width) < (_a4HeightMm / s.height) ? _a4WidthMm / s.width : _a4HeightMm / s.height;
    final k = fit * (_adj[i].zoom / 100);
    final w = s.width * k;
    final h = s.height * k;
    return ((_a4WidthMm - w) / 2 + _adj[i].x, (_a4HeightMm - h) / 2 + _adj[i].y, w, h);
  }

  Future<void> _export() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final doc = pw.Document();
      final indices = _allPages ? List.generate(_pages.length, (i) => i) : [_current];
      for (final i in indices) {
        final (l, t, w, h) = _rect(i);
        final img = pw.MemoryImage(_pages[i]);
        doc.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Stack(children: [
            pw.Positioned(
              left: l * PdfPageFormat.mm,
              top: t * PdfPageFormat.mm,
              child: pw.Image(img, width: w * PdfPageFormat.mm, height: h * PdfPageFormat.mm),
            ),
          ]),
        ));
      }
      final bytes = await doc.save();
      final base = _fileName.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
      final name = '${base.isEmpty ? 'document' : base}-letterhead-ready.pdf';
      final saved = await DownloadSaver.savePdf(name, bytes);
      messenger.showSnackBar(SnackBar(
        content: Text('Saved to ${saved.locationLabel}: $name'),
        action: saved.canOpen ? SnackBarAction(label: 'Open', onPressed: () => saved.open()) : null,
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not export: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _stepper(String label, String hint, double value, String unit, double step,
      void Function(_Adj a, double v) set) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                Text(hint, style: AppText.caption),
              ],
            ),
          ),
          _StepButton(
            icon: Icons.remove_rounded,
            tooltip: 'Decrease $label',
            onTap: () => _change((a) => set(a, value - step)),
          ),
          SizedBox(
            width: 86,
            child: Center(
              child: Text(
                '${value.toStringAsFixed(1)} $unit',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          _StepButton(
            icon: Icons.add_rounded,
            tooltip: 'Increase $label',
            onTap: () => _change((a) => set(a, value + step)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPdf = _pages.isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: proLightAppBar(
        context,
        title: 'Align & export PDF',
        subtitle: 'Letter head · A4 print layout',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const ProNote(
            'Upload the PDF with your letter content, adjust its position on an A4 sheet, then export a '
            'print-ready PDF for pre-printed letterhead paper. The letterhead artwork is not included.',
            tone: ProNoteTone.info,
          ),
          const SizedBox(height: 14),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ProIconWell(
                      icon: Icons.picture_as_pdf_rounded,
                      color: hasPdf ? AppColors.danger : AppColors.primary,
                      size: 40,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasPdf ? _fileName : 'No PDF chosen',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                          Text(
                            hasPdf
                                ? '${_pages.length} ${_pages.length == 1 ? 'page' : 'pages'}'
                                : 'Letter content as a PDF',
                            style: AppText.caption,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (hasPdf)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pick,
                    icon: const Icon(Icons.upload_file_rounded, size: 18),
                    label: const Text('Choose another PDF'),
                  )
                else
                  FilledButton.icon(
                    onPressed: _busy ? null : _pick,
                    icon: const Icon(Icons.upload_file_rounded, size: 18),
                    label: const Text('Choose PDF'),
                  ),
                if (_busy) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      color: AppColors.primary,
                      backgroundColor: AppColors.hairlineSoft,
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  ProNote(_error!, tone: ProNoteTone.bad),
                ],
              ],
            ),
          ),
          if (hasPdf) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                _StepButton(
                  icon: Icons.chevron_left_rounded,
                  tooltip: 'Previous page',
                  onTap: _current > 0 ? () => setState(() => _current--) : null,
                ),
                Expanded(
                  child: Text(
                    'Page ${_current + 1} of ${_pages.length}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkSoft,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                _StepButton(
                  icon: Icons.chevron_right_rounded,
                  tooltip: 'Next page',
                  onTap: _current < _pages.length - 1 ? () => setState(() => _current++) : null,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: AspectRatio(
                aspectRatio: _a4WidthMm / _a4HeightMm,
                child: LayoutBuilder(builder: (ctx, c) {
                  final (l, t, w, h) = _rect(_current);
                  final sx = c.maxWidth / _a4WidthMm;
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: AppColors.hairline),
                      boxShadow: AppShadows.card,
                    ),
                    child: ClipRect(
                      child: Stack(children: [
                        Positioned(
                          left: l * sx,
                          top: t * sx,
                          width: w * sx,
                          height: h * sx,
                          child: Image.memory(_pages[_current], fit: BoxFit.fill),
                        ),
                      ]),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                _ValueChip(label: 'X', value: '${_a.x.toStringAsFixed(1)} mm'),
                _ValueChip(label: 'Y', value: '${_a.y.toStringAsFixed(1)} mm'),
                _ValueChip(label: 'Zoom', value: '${_a.zoom.toStringAsFixed(1)} %'),
              ],
            ),
            const SizedBox(height: 14),
            GlassCard(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ProSectionHeader(
                    title: 'Position',
                    actionLabel: 'Reset',
                    onAction: () => _change((a) {
                      a.x = 0;
                      a.y = 0;
                      a.zoom = 100;
                    }),
                  ),
                  _stepper('X', 'Left / right offset', _a.x, 'mm', 1, (a, v) => a.x = v),
                  const Divider(height: 1),
                  _stepper('Y', 'Up / down offset', _a.y, 'mm', 1, (a, v) => a.y = v),
                  const Divider(height: 1),
                  _stepper('Zoom', 'Scale 50 – 150%', _a.zoom, '%', 1,
                      (a, v) => a.zoom = v.clamp(50, 150).toDouble()),
                ],
              ),
            ),
            const SizedBox(height: 14),
            GlassCard(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Apply adjustments to all pages',
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
                    ),
                    value: _applyToAll,
                    onChanged: (v) => setState(() => _applyToAll = v),
                  ),
                  const SizedBox(height: 6),
                  ProField(
                    label: 'Export',
                    child: SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Current page')),
                          ButtonSegment(value: true, label: Text('All pages')),
                        ],
                        selected: {_allPages},
                        onSelectionChanged: (s) => setState(() => _allPages = s.first),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: hasPdf
          ? ProBottomBar(
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _export,
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  label: const Text('Export A4 PDF'),
                ),
              ],
            )
          : null,
    );
  }
}

/// 40px round-cornered stepper / pager button.
class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 20, color: enabled ? AppColors.ink : AppColors.faint),
          ),
        ),
      ),
    );
  }
}

class _ValueChip extends StatelessWidget {
  const _ValueChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(
            text: '$label  ',
            style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.muted),
          ),
          TextSpan(text: value),
        ]),
        style: const TextStyle(
          fontSize: 12.5,
          color: AppColors.ink,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
