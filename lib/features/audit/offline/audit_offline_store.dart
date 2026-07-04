// ─────────────────────────────────────────────────────────────────────────────
//  Branch Internal Audit — OFFLINE store (dependency-free).
//
//  Persists, in the app documents dir (path_provider) as JSON files:
//   • per-execution DRAFTS (answers/observations/compliance/rating/summary) so an
//     auditor can fill offline and survive app restarts, and
//   • a SYNC QUEUE of pending mutations (incl. staged photo files) replayed when
//     connectivity returns.
//  No new packages: online/offline is inferred from dio network errors at call sites.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// A locally-held draft of one execution's fill state.
class AuditDraft {
  final int executionId;
  final Map<int, String?> answers; // questionId -> YES/NO/NA/null
  final Map<int, String> observations; // questionId -> text
  final Map<int, String> compliance; // questionId -> text
  final Map<String, dynamic>? rating;
  final Map<String, dynamic>? summary;
  final String updatedAt;

  const AuditDraft({
    required this.executionId,
    this.answers = const {},
    this.observations = const {},
    this.compliance = const {},
    this.rating,
    this.summary,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'executionId': executionId,
        'answers': answers.map((k, v) => MapEntry(k.toString(), v)),
        'observations': observations.map((k, v) => MapEntry(k.toString(), v)),
        'compliance': compliance.map((k, v) => MapEntry(k.toString(), v)),
        'rating': rating,
        'summary': summary,
        'updatedAt': updatedAt,
      };

  static AuditDraft fromJson(Map<String, dynamic> j) {
    Map<int, String?> ansMap(dynamic m) => (m is Map ? m : const {})
        .map((k, v) => MapEntry(int.tryParse(k.toString()) ?? -1, v as String?));
    Map<int, String> txtMap(dynamic m) => (m is Map ? m : const {})
        .map((k, v) => MapEntry(int.tryParse(k.toString()) ?? -1, (v ?? '').toString()));
    return AuditDraft(
      executionId: (j['executionId'] as num).toInt(),
      answers: ansMap(j['answers']),
      observations: txtMap(j['observations']),
      compliance: txtMap(j['compliance']),
      rating: j['rating'] is Map<String, dynamic> ? j['rating'] as Map<String, dynamic> : null,
      summary: j['summary'] is Map<String, dynamic> ? j['summary'] as Map<String, dynamic> : null,
      updatedAt: (j['updatedAt'] ?? '').toString(),
    );
  }
}

/// One queued mutation to replay against the backend when online.
class AuditQueueItem {
  /// SAVE_RESPONSES | SAVE_RATING | SAVE_SUMMARY | ADD_ANNEXURE | SUBMIT | UPLOAD_PROOF
  final String id;
  final String type;
  final int executionId;
  final Map<String, dynamic> payload;
  final String createdAt;

  const AuditQueueItem({
    required this.id,
    required this.type,
    required this.executionId,
    required this.payload,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'executionId': executionId,
        'payload': payload,
        'createdAt': createdAt,
      };

  static AuditQueueItem fromJson(Map<String, dynamic> j) => AuditQueueItem(
        id: j['id'].toString(),
        type: j['type'].toString(),
        executionId: (j['executionId'] as num).toInt(),
        payload: (j['payload'] is Map<String, dynamic>)
            ? j['payload'] as Map<String, dynamic>
            : <String, dynamic>{},
        createdAt: (j['createdAt'] ?? '').toString(),
      );
}

class AuditOfflineStore {
  Directory? _cached;

  Future<Directory> _dir() async {
    if (_cached != null) return _cached!;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/audit_offline');
    if (!await dir.exists()) await dir.create(recursive: true);
    _cached = dir;
    return dir;
  }

  // ── Drafts ──
  Future<void> saveDraft(AuditDraft draft) async {
    final f = File('${(await _dir()).path}/draft_${draft.executionId}.json');
    await f.writeAsString(jsonEncode(draft.toJson()));
  }

  Future<AuditDraft?> loadDraft(int executionId) async {
    final f = File('${(await _dir()).path}/draft_$executionId.json');
    if (!await f.exists()) return null;
    try {
      return AuditDraft.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearDraft(int executionId) async {
    final f = File('${(await _dir()).path}/draft_$executionId.json');
    if (await f.exists()) await f.delete();
  }

  // ── Sync queue ──
  Future<File> _queueFile() async => File('${(await _dir()).path}/sync_queue.json');

  Future<List<AuditQueueItem>> queue() async {
    final f = await _queueFile();
    if (!await f.exists()) return [];
    try {
      final list = jsonDecode(await f.readAsString());
      return (list is List ? list : const [])
          .whereType<Map<String, dynamic>>()
          .map(AuditQueueItem.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeQueue(List<AuditQueueItem> items) async {
    final f = await _queueFile();
    await f.writeAsString(jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  Future<void> enqueue(AuditQueueItem item) async {
    final items = await queue();
    items.add(item);
    await _writeQueue(items);
  }

  Future<void> dequeue(String id) async {
    final items = await queue();
    items.removeWhere((e) => e.id == id);
    await _writeQueue(items);
  }

  Future<int> pendingCount() async => (await queue()).length;

  /// Copies a picked photo into the offline dir so it survives until upload.
  Future<String> stagePhoto(String sourcePath) async {
    final ext = sourcePath.contains('.') ? sourcePath.substring(sourcePath.lastIndexOf('.')) : '.jpg';
    final dest = File('${(await _dir()).path}/proof_${_id()}$ext');
    await File(sourcePath).copy(dest.path);
    return dest.path;
  }

  static int _seq = 0;
  // Monotonic id: timestamp + process-local counter, so two calls in the same microsecond
  // (Windows has a coarse clock) never collide — important so queue items aren't deduped away.
  static String _id() => '${DateTime.now().microsecondsSinceEpoch}_${_seq++}';
  static String newItemId() => _id();
}

final auditOfflineStoreProvider = Provider<AuditOfflineStore>((_) => AuditOfflineStore());
