// Pure-Dart round-trip tests for the audit offline draft + sync-queue models.
// (No path_provider / IO — just the JSON (de)serialisation the sync engine relies on.)

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nava360/features/audit/offline/audit_offline_store.dart';

void main() {
  test('AuditDraft survives a JSON round-trip (int keys preserved)', () {
    final draft = AuditDraft(
      executionId: 42,
      answers: {1: 'YES', 2: 'NO', 3: null},
      observations: {1: 'looks fine', 2: 'missing register'},
      compliance: {2: 'will fix'},
      rating: {'totalCustomers': 120},
      summary: {'auditorFinalRemark': 'ok'},
      updatedAt: '2026-06-30T10:00:00.000',
    );

    final back = AuditDraft.fromJson(jsonDecode(jsonEncode(draft.toJson())) as Map<String, dynamic>);

    expect(back.executionId, 42);
    expect(back.answers[1], 'YES');
    expect(back.answers[2], 'NO');
    expect(back.answers.containsKey(3), true);
    expect(back.answers[3], isNull);
    expect(back.observations[2], 'missing register');
    expect(back.compliance[2], 'will fix');
    expect(back.rating?['totalCustomers'], 120);
    expect(back.summary?['auditorFinalRemark'], 'ok');
  });

  test('AuditQueueItem survives a JSON round-trip', () {
    final item = AuditQueueItem(
      id: 'abc123',
      type: 'SAVE_RESPONSES',
      executionId: 7,
      payload: {
        'responses': [
          {'questionId': 10, 'answer': 'NO', 'auditorObservation': 'x', 'complianceByBm': null},
        ],
      },
      createdAt: '2026-06-30T10:00:00.000',
    );

    final back = AuditQueueItem.fromJson(jsonDecode(jsonEncode(item.toJson())) as Map<String, dynamic>);

    expect(back.id, 'abc123');
    expect(back.type, 'SAVE_RESPONSES');
    expect(back.executionId, 7);
    expect((back.payload['responses'] as List).length, 1);
    expect((back.payload['responses'] as List).first['answer'], 'NO');
  });

  test('newItemId returns distinct ids', () {
    final a = AuditOfflineStore.newItemId();
    final b = AuditOfflineStore.newItemId();
    expect(a, isNotEmpty);
    expect(a == b, isFalse);
  });
}
