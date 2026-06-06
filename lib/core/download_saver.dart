import 'dart:io';

import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Result of saving a file to the device's user-visible storage.
class SavedDownload {
  SavedDownload({required this.locationLabel, this.androidUri, this.filePath});

  /// Human-friendly destination, e.g. "Downloads" or "Files app".
  final String locationLabel;

  /// `content://` URI returned by Android MediaStore (API 29+).
  final String? androidUri;

  /// Absolute filesystem path (iOS Documents, or Android legacy Downloads).
  final String? filePath;

  bool get canOpen => androidUri != null || filePath != null;

  /// Opens the saved file in the system viewer.
  Future<void> open() async {
    final uri = androidUri;
    final path = filePath;
    if (uri != null) {
      await DownloadSaver.channel.invokeMethod<void>('openDownload', {
        'uri': uri,
        'mimeType': 'application/pdf',
      });
    } else if (path != null) {
      await OpenFilex.open(path);
    }
  }
}

/// Saves binary content to the device's public/user-visible storage —
/// the phone's Downloads folder on Android, the Files app on iOS — rather than
/// the app's private sandbox.
class DownloadSaver {
  static const MethodChannel channel = MethodChannel('app/downloads');

  /// Saves [bytes] as [fileName]. On Android this lands in the public Downloads
  /// collection via MediaStore (no permission on API 29+; falls back to a
  /// permissioned legacy write below that). On iOS it goes to the app's
  /// Documents directory, which is exposed in the Files app.
  static Future<SavedDownload> savePdf(String fileName, Uint8List bytes) async {
    if (Platform.isAndroid) {
      final res = await channel.invokeMethod<String>('saveToDownloads', {
        'fileName': fileName,
        'bytes': bytes,
        'mimeType': 'application/pdf',
      });
      final value = res ?? '';
      if (value.startsWith('content://')) {
        return SavedDownload(locationLabel: 'Downloads', androidUri: value);
      }
      return SavedDownload(
        locationLabel: 'Downloads',
        filePath: value.isEmpty ? null : value,
      );
    }
    // iOS and others: app Documents directory, visible via the Files app
    // (UIFileSharingEnabled + LSSupportsOpeningDocumentsInPlace in Info.plist).
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return SavedDownload(locationLabel: 'Files app', filePath: file.path);
  }
}
