// ─────────────────────────────────────────────────────────────────────────────
//  Branch Internal Audit — OFFLINE sync service.
//  Replays queued mutations against the backend. Stops on the first network error
//  (still offline) and leaves the rest queued; drops items that fail with a real
//  server/validation error so a single bad item can't block the queue forever.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../audit_repository.dart';
import 'audit_offline_store.dart';

/// True when an error is a connectivity problem (treat as "still offline"),
/// not a real server response.
bool isNetworkError(Object e) {
  if (e is DioException) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return true;
      case DioExceptionType.unknown:
        return e.response == null;
      default:
        return false;
    }
  }
  if (e is ApiException) return e.statusCode == null; // no HTTP response reached
  return e is SocketException;
}

class AuditSyncResult {
  final int synced;
  final int remaining;
  final bool stillOffline;
  const AuditSyncResult(this.synced, this.remaining, this.stillOffline);
}

class AuditSyncService {
  AuditSyncService(this._repo, this._store);
  final AuditRepository _repo;
  final AuditOfflineStore _store;

  /// Flushes the queue in order. Returns how many synced + how many remain.
  Future<AuditSyncResult> flush() async {
    final items = await _store.queue();
    int synced = 0;
    for (final it in items) {
      try {
        await _apply(it);
        await _store.dequeue(it.id);
        synced++;
      } catch (e) {
        if (isNetworkError(e)) {
          return AuditSyncResult(synced, items.length - synced, true);
        }
        // Non-network failure → drop the item (don't block the queue).
        await _store.dequeue(it.id);
      }
    }
    return AuditSyncResult(synced, 0, false);
  }

  Future<void> _apply(AuditQueueItem it) async {
    final p = it.payload;
    switch (it.type) {
      case 'SAVE_RESPONSES':
        final responses = (p['responses'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
            .toList();
        await _repo.saveResponses(it.executionId, responses);
        break;
      case 'SAVE_RATING':
        await _repo.saveRating(it.executionId, Map<String, dynamic>.from(p));
        break;
      case 'SAVE_SUMMARY':
        await _repo.saveExecutiveSummary(it.executionId, Map<String, dynamic>.from(p));
        break;
      case 'ADD_ANNEXURE':
        await _repo.addAnnexure(it.executionId, p['type'].toString(),
            Map<String, dynamic>.from(p['body'] as Map? ?? const {}));
        break;
      case 'SUBMIT':
        await _repo.submitAudit(it.executionId);
        break;
      case 'UPLOAD_PROOF':
        final path = p['filePath']?.toString();
        if (path == null || !await File(path).exists()) return; // file gone — skip
        final form = FormData.fromMap({
          'file': await MultipartFile.fromFile(path),
          'parentType': p['parentType'] ?? 'EXECUTION',
          'parentId': p['parentId'],
          if (p['executionId'] != null) 'executionId': p['executionId'],
          if (p['caption'] != null) 'caption': p['caption'],
          if (p['latitude'] != null) 'latitude': p['latitude'],
          if (p['longitude'] != null) 'longitude': p['longitude'],
          if (p['capturedAt'] != null) 'capturedAt': p['capturedAt'],
        });
        await _repo.uploadProof(form);
        try { await File(path).delete(); } catch (_) {}
        break;
    }
  }
}

final auditSyncServiceProvider = Provider<AuditSyncService>(
  (ref) => AuditSyncService(ref.watch(auditRepositoryProvider), ref.watch(auditOfflineStoreProvider)),
);

/// Count of pending offline mutations (drives the "N pending" badge).
final auditPendingCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(auditOfflineStoreProvider).pendingCount(),
);
