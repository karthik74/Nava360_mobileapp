// ─────────────────────────────────────────────────────────────────────────────
//  Branch Internal Audit — photo proof capture.
//
//  A reusable button + flow that:
//    • picks/captures a photo with image_picker (imageQuality 60 ⇒ COMPRESSION),
//    • reads the current GPS fix with geolocator (GEOTAG, gracefully degrades),
//    • stamps DateTime.now() (TIMESTAMP),
//    • builds multipart FormData and POSTs via AuditRepository.uploadProof.
//
//  Geolocation/permission handling mirrors live_location_responder.dart — it
//  never throws if location is unavailable; the proof still uploads.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import 'audit_repository.dart';
import 'offline/audit_offline_store.dart';
import 'offline/audit_sync_service.dart';

/// Tries to read a current GPS fix, falling back to the last known position.
/// Returns null (lat/lng) silently when location is unavailable or denied.
Future<({double? lat, double? lng})> _tryLocation() async {
  try {
    final serviceOn = await Geolocator.isLocationServiceEnabled();
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    final granted = perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
    if (!granted || !serviceOn) return (lat: null, lng: null);

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 12),
      );
      return (lat: pos.latitude, lng: pos.longitude);
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      return (lat: last?.latitude, lng: last?.longitude);
    }
  } catch (_) {
    return (lat: null, lng: null);
  }
}

Future<ImageSource?> _pickSource(BuildContext context) {
  return showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: AppColors.surface,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Icons.photo_camera_rounded,
                color: AppColors.primary),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: Icon(Icons.photo_library_rounded,
                color: AppColors.primary),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
}

/// Captures (or picks) a compressed, geotagged, timestamped photo and uploads it
/// as proof for the given parent. Returns true on success. Shows its own
/// snackbars for feedback. Safe to call from any widget with a [WidgetRef].
Future<bool> capturePhotoProof(
  BuildContext context,
  WidgetRef ref, {
  required String parentType, // RESPONSE | FINDING | EXECUTION
  required int parentId,
  int? executionId,
  String? caption,
}) async {
  final source = await _pickSource(context);
  if (source == null || !context.mounted) return false;

  final picked = await ImagePicker().pickImage(
    source: source,
    imageQuality: 60, // COMPRESSION
    maxWidth: 1600,
  );
  if (picked == null) return false;
  if (!context.mounted) return false;

  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.showSnackBar(
    const SnackBar(content: Text('Uploading photo proof…')),
  );

  final loc = await _tryLocation();
  final capturedAt = DateTime.now().toIso8601String();
  final fileName = picked.name.contains('.') ? picked.name : '${picked.name}.jpg';

  try {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(picked.path, filename: fileName),
      'parentType': parentType,
      'parentId': parentId,
      if (executionId != null) 'executionId': executionId,
      if (caption != null && caption.trim().isNotEmpty) 'caption': caption.trim(),
      if (loc.lat != null) 'latitude': loc.lat,
      if (loc.lng != null) 'longitude': loc.lng,
      'capturedAt': capturedAt,
    });
    await ref.read(auditRepositoryProvider).uploadProof(form);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(loc.lat == null
            ? 'Photo proof uploaded (no location).'
            : 'Photo proof uploaded with location.'),
        backgroundColor: AppColors.success,
      ),
    );
    return true;
  } catch (e) {
    if (isNetworkError(e)) {
      // Offline: stage the photo locally and queue the upload for later sync.
      final store = ref.read(auditOfflineStoreProvider);
      final stored = await store.stagePhoto(picked.path);
      await store.enqueue(AuditQueueItem(
        id: AuditOfflineStore.newItemId(),
        type: 'UPLOAD_PROOF',
        executionId: executionId ?? parentId,
        payload: {
          'parentType': parentType,
          'parentId': parentId,
          if (executionId != null) 'executionId': executionId,
          if (caption != null && caption.trim().isNotEmpty) 'caption': caption.trim(),
          if (loc.lat != null) 'latitude': loc.lat,
          if (loc.lng != null) 'longitude': loc.lng,
          'capturedAt': capturedAt,
          'filePath': stored,
        },
        createdAt: DateTime.now().toIso8601String(),
      ));
      ref.invalidate(auditPendingCountProvider);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(const SnackBar(content: Text('Offline — photo saved, will upload when online.')));
      return true;
    }
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text('Upload failed: $e'),
        backgroundColor: AppColors.danger,
      ),
    );
    return false;
  }
}

/// A compact "Add photo proof" button wired to [capturePhotoProof]. Used on
/// question cards and finding screens.
class AddPhotoProofButton extends ConsumerWidget {
  const AddPhotoProofButton({
    super.key,
    required this.parentType,
    required this.parentId,
    this.executionId,
    this.label = 'Add photo proof',
    this.onUploaded,
  });

  final String parentType;
  final int parentId;
  final int? executionId;
  final String label;
  final VoidCallback? onUploaded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton.icon(
      onPressed: () async {
        final ok = await capturePhotoProof(
          context,
          ref,
          parentType: parentType,
          parentId: parentId,
          executionId: executionId,
        );
        if (ok) onUploaded?.call();
      },
      icon: const Icon(Icons.add_a_photo_rounded, size: 16),
      label: Text(label),
    );
  }
}

/// A small inline preview list of uploaded proofs for a parent.
class ProofThumb extends StatelessWidget {
  const ProofThumb({super.key, required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.hairline),
        ),
        child: const Icon(Icons.image_rounded, size: 18, color: AppColors.muted),
      );
    }
    final isLocal = !(url!.startsWith('http'));
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: isLocal
          ? Image.file(File(url!), width: 48, height: 48, fit: BoxFit.cover)
          : Image.network(url!, width: 48, height: 48, fit: BoxFit.cover),
    );
  }
}
