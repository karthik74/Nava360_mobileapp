import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'it_asset_models.dart';

final itAssetRepositoryProvider =
    Provider((ref) => ItAssetRepository(ref.watch(apiClientProvider)));

List<Map<String, dynamic>> _asList(dynamic d) =>
    ((d as List?) ?? const []).cast<Map<String, dynamic>>();

/// Admin Tools · IT Assets — mobile-relevant slice only: the signed-in
/// employee's own assigned forms, and submitting answers. Template
/// authoring/assignment/reporting stay web-only.
class ItAssetRepository {
  ItAssetRepository(this._api);
  final ApiClient _api;

  static const _base = '/api/admin-tools/it-assets';

  Future<List<ItAssetFormEntry>> myEntries() {
    return _api.get<List<ItAssetFormEntry>>(
      '$_base/entries/my',
      parse: (d) => _asList(d).map(ItAssetFormEntry.fromJson).toList(),
    );
  }

  /// Form templates (id -> name) for the report picker. Needs ADMIN_IT_ASSET_VIEW.
  Future<List<({int id, String name})>> templates() {
    return _api.get<List<({int id, String name})>>(
      '$_base/templates',
      query: {'size': 100},
      parse: (d) => _asList((d as Map?)?['content'])
          .map((m) => (id: (m['id'] as num).toInt(), name: (m['name'] as String?) ?? 'Form #${m['id']}'))
          .toList(),
    );
  }

  /// Excel report for one form — either a single `date` or a `from`..`to` range (yyyy-MM-dd).
  Future<Uint8List> exportReport(int templateId, {String? date, String? from, String? to}) {
    return _api.getBytes('$_base/report/export', query: {
      'templateId': templateId,
      if (date != null) 'date': date,
      if (from != null) 'from': from,
      if (to != null) 'to': to,
    });
  }

  Future<ItAssetFormEntry> fill(int entryId, Map<String, String> answers) {
    return _api.put<ItAssetFormEntry>(
      '$_base/entries/$entryId/fill',
      body: {'responseData': jsonEncode(answers)},
      parse: (d) => ItAssetFormEntry.fromJson(d as Map<String, dynamic>),
    );
  }
}
