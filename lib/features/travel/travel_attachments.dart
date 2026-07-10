import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
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
      backgroundColor: AppColors.surface,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.photo_camera_rounded, color: AppColors.primary),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_rounded, color: AppColors.primary),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionHeader(title: title, subtitle: subtitle),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => _addImage(context),
              icon: const Icon(Icons.add_a_photo_rounded, size: 18),
              label: const Text('Add Image'),
            ),
            OutlinedButton.icon(
              onPressed: () => _addDocument(context),
              icon: const Icon(Icons.attach_file_rounded, size: 18),
              label: const Text('Add File'),
            ),
          ],
        ),
        if (files.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (int i = 0; i < files.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassCard(
                padding: const EdgeInsets.all(10),
                shadow: AppShadows.soft,
                child: Row(
                  children: [
                    if (_isImage(files[i].fileName))
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(File(files[i].path),
                            width: 44, height: 44, fit: BoxFit.cover),
                      )
                    else
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.picture_as_pdf_rounded, color: AppColors.primary),
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        files[i].fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        files.removeAt(i);
                        onChanged();
                      },
                      icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                      tooltip: 'Remove',
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}
