import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'download_saver.dart';

const _xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Fetches an Excel report from the server, saves it to the phone's Downloads and offers to open it.
/// The server decides what the caller may see (everything for a full-access user, their own branch otherwise).
Future<void> downloadExcelReport(BuildContext context, Future<Uint8List> Function() fetch, String fileName) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Preparing report…')));
  try {
    final bytes = await fetch();
    final saved = await DownloadSaver.save(fileName, bytes, mimeType: _xlsxMime);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text('Saved to ${saved.locationLabel}: $fileName'),
      action: saved.canOpen ? SnackBarAction(label: 'Open', onPressed: () => saved.open()) : null,
    ));
  } catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text('Could not download the report: $e')));
  }
}
