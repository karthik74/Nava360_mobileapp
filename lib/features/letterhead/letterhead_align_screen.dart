import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/download_saver.dart';

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

  Widget _stepper(String label, double value, String unit, double step, void Function(_Adj a, double v) set) {
    return Row(
      children: [
        SizedBox(width: 60, child: Text(label)),
        IconButton(onPressed: () => _change((a) => set(a, value - step)), icon: const Icon(Icons.remove_circle_outline)),
        Expanded(child: Center(child: Text('${value.toStringAsFixed(1)} $unit'))),
        IconButton(onPressed: () => _change((a) => set(a, value + step)), icon: const Icon(Icons.add_circle_outline)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPdf = _pages.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Align & export PDF')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Upload the PDF with your letter content, adjust its position on an A4 sheet, then export a '
            'print-ready PDF for pre-printed letterhead paper. The letterhead artwork is not included.',
            style: TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.upload_file_rounded),
            label: Text(hasPdf ? 'Choose another PDF' : 'Choose PDF'),
          ),
          if (_busy) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
          if (hasPdf) ...[
            const SizedBox(height: 12),
            Text(_fileName, style: const TextStyle(fontWeight: FontWeight.w700)),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                    onPressed: _current > 0 ? () => setState(() => _current--) : null,
                    icon: const Icon(Icons.chevron_left)),
                Text('Page ${_current + 1} of ${_pages.length}'),
                IconButton(
                    onPressed: _current < _pages.length - 1 ? () => setState(() => _current++) : null,
                    icon: const Icon(Icons.chevron_right)),
              ],
            ),
            Center(
              child: AspectRatio(
                aspectRatio: _a4WidthMm / _a4HeightMm,
                child: LayoutBuilder(builder: (ctx, c) {
                  final (l, t, w, h) = _rect(_current);
                  final sx = c.maxWidth / _a4WidthMm;
                  return Container(
                    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black26)),
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
            const SizedBox(height: 8),
            _stepper('X', _a.x, 'mm', 1, (a, v) => a.x = v),
            _stepper('Y', _a.y, 'mm', 1, (a, v) => a.y = v),
            _stepper('Zoom', _a.zoom, '%', 1, (a, v) => a.zoom = v.clamp(50, 150).toDouble()),
            Row(children: [
              TextButton(onPressed: () => _change((a) {
                    a.x = 0;
                    a.y = 0;
                    a.zoom = 100;
                  }), child: const Text('Reset')),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Apply adjustments to all pages'),
              value: _applyToAll,
              onChanged: (v) => setState(() => _applyToAll = v),
            ),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Current page')),
                ButtonSegment(value: true, label: Text('All pages')),
              ],
              selected: {_allPages},
              onSelectionChanged: (s) => setState(() => _allPages = s.first),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _export,
              icon: const Icon(Icons.picture_as_pdf_rounded),
              label: const Text('Export A4 PDF'),
            ),
          ],
        ],
      ),
    );
  }
}
