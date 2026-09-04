// ─────────────────────────────────────────────────────────────────────────────
//  CSV building + saving for the MIS report exports (client details, daily-plan
//  reports, the dashboard's Month Highlights). The web builds a Blob and clicks
//  a link; on mobile the file lands in Downloads / the Files app and the user is
//  offered a tap to open it.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/download_saver.dart';
import '../../core/theme.dart';

/// CSV-safe: quote when the value could break a cell, double any inner quote.
String misCsvCell(Object? v) {
  if (v == null) return '';
  final s = v.toString();
  return RegExp(r'[",\n\r]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
}

/// Join [rows] into a CSV document. Rows are lists of raw cell values.
String misCsvDocument(List<List<Object?>> rows) =>
    rows.map((r) => r.map(misCsvCell).join(',')).join('\r\n');

/// Turn a title into a filename-safe slug.
String misSlug(String s) {
  final out = s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return out.isEmpty ? 'export' : out;
}

/// Writes [csv] to the device as [fileName] and tells the user where it went.
/// Returns true when the file was saved.
///
/// A UTF-8 BOM is prepended so Excel opens it as UTF-8 instead of mangling
/// non-ASCII branch and client names.
Future<bool> misSaveCsv(
  BuildContext context,
  String fileName,
  String csv,
) =>
    misSaveBytes(
      context,
      fileName,
      Uint8List.fromList(utf8.encode('﻿$csv')),
      mimeType: 'text/csv',
      noun: 'file',
    );

/// Writes a rasterized PNG (e.g. a `RenderRepaintBoundary.toImage()` capture)
/// to the device as [fileName] and tells the user where it went. Mirrors the
/// web's `downloadImage` — a genuine save, same as [misSaveCsv], not a share
/// sheet.
Future<bool> misSaveImage(
  BuildContext context,
  String fileName,
  Uint8List bytes,
) =>
    misSaveBytes(context, fileName, bytes, mimeType: 'image/png', noun: 'image');

/// Shared save + snackbar plumbing behind [misSaveCsv] and [misSaveImage].
Future<bool> misSaveBytes(
  BuildContext context,
  String fileName,
  Uint8List bytes, {
  required String mimeType,
  required String noun,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final saved = await DownloadSaver.save(fileName, bytes, mimeType: mimeType);
    messenger?.showSnackBar(
      SnackBar(
        content: Text('Saved $fileName to ${saved.locationLabel}'),
        behavior: SnackBarBehavior.floating,
        action: saved.canOpen
            ? SnackBarAction(
                label: 'Open',
                textColor: Colors.white,
                onPressed: () => saved.open(),
              )
            : null,
      ),
    );
    return true;
  } catch (e) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text('Could not save the $noun: $e'),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
      ),
    );
    return false;
  }
}
