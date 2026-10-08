import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import 'travel_models.dart';

/// Stages bills/evidence on-device (camera photo, gallery image, or PDF) for a
/// plan / claim / expense before they're uploaded as multipart. Mutates [files]
/// and calls [onChanged] so the parent re-renders. Mirrors the whistleblower
/// EvidenceSection picker but emits [TravelUploadFile]s (no audio).
class TravelFilePicker extends StatelessWidget {
  const TravelFilePicker({
    super.key,
    required this.files,
    required this.onChanged,
    this.title = 'Bills / Attachments',
    this.subtitle = 'Optional — photos of receipts or a PDF',
  });

  final List<TravelUploadFile> files;
  final VoidCallback onChanged;
  final String title;
  final String subtitle;

  Future<void> _addImage(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFC6D3D6),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Add a receipt photo',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.35,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ProListGroup(
                  children: [
                    ProListRow(
                      leading: ProIconWell(
                          icon: Icons.photo_camera_rounded, color: AppColors.primary),
                      title: 'Take a photo',
                      onTap: () => Navigator.pop(context, ImageSource.camera),
                    ),
                    ProListRow(
                      leading: ProIconWell(
                          icon: Icons.photo_library_rounded, color: AppColors.primary),
                      title: 'Choose from gallery',
                      onTap: () => Navigator.pop(context, ImageSource.gallery),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (source == null) return;
    final picked =
        await ImagePicker().pickImage(source: source, imageQuality: 80, maxWidth: 2000);
    if (picked == null) return;
    files.add(TravelUploadFile(path: picked.path, fileName: _name(picked.path, 'jpg')));
    onChanged();
  }

  Future<void> _addDocument(BuildContext context) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      allowMultiple: true,
    );
    if (res == null) return;
    for (final f in res.files) {
      final path = f.path;
      if (path == null) continue;
      files.add(TravelUploadFile(path: path, fileName: f.name));
    }
    onChanged();
  }

  static String _name(String path, String fallbackExt) {
    final base = path.split(Platform.pathSeparator).last;
    return base.contains('.') ? base : '$base.$fallbackExt';
  }

  bool _isImage(String name) {
    final n = name.toLowerCase();
    return n.endsWith('.jpg') || n.endsWith('.jpeg') || n.endsWith('.png') || n.endsWith('.webp');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProSectionHeader(title: title, subtitle: subtitle),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _UploadTile(
                icon: Icons.add_a_photo_rounded,
                label: 'Add Image',
                hint: 'Camera or gallery',
                onTap: () => _addImage(context),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _UploadTile(
                icon: Icons.attach_file_rounded,
                label: 'Add File',
                hint: 'PDF, JPG or PNG',
                onTap: () => _addDocument(context),
              ),
            ),
          ],
        ),
        if (files.isNotEmpty) ...[
          const SizedBox(height: 12),
          ProListGroup(
            dividerIndent: 68,
            children: [
              for (int i = 0; i < files.length; i++)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  child: Row(
                    children: [
                      if (_isImage(files[i].fileName))
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(File(files[i].path),
                              width: 44, height: 44, fit: BoxFit.cover),
                        )
                      else
                        ProIconWell(
                          icon: Icons.picture_as_pdf_rounded,
                          color: AppColors.primary,
                          size: 44,
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          files[i].fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w500,
                              color: AppColors.ink),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          files.removeAt(i);
                          onChanged();
                        },
                        icon: const Icon(Icons.delete_outline_rounded,
                            size: 20, color: AppColors.danger),
                        tooltip: 'Remove',
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Dashed receipt-upload tile.
class _UploadTile extends StatelessWidget {
  const _UploadTile({
    required this.icon,
    required this.label,
    required this.hint,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: CustomPaint(
          painter: _DashedRRectPainter(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
            child: Column(
              children: [
                ProIconWell(icon: icon, color: AppColors.primary),
                const SizedBox(height: 8),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.ink)),
                Text(hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14));
    canvas.drawRRect(rrect, Paint()..color = AppColors.surfaceAlt);
    final path = Path()..addRRect(rrect.deflate(0.5));
    final paint = Paint()
      ..color = const Color(0xFFC6D3D6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
        d += 9;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
