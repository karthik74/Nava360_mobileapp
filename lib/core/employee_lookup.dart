// ─────────────────────────────────────────────────────────────────────────────
//  Lightweight, org-wide employee lookup for pickers/dropdowns usable by ANY
//  authenticated user (e.g. whistleblower "person(s) involved"). Backed by the
//  GET /api/employees/lookup endpoint (id/code/name only — no sensitive data).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

class EmployeeLookup {
  final int id;
  final String? code;
  final String name;

  const EmployeeLookup({required this.id, this.code, required this.name});

  factory EmployeeLookup.fromJson(Map<String, dynamic> j) => EmployeeLookup(
        id: (j['id'] as num).toInt(),
        code: j['employeeCode'] as String?,
        name: (j['name'] ?? '').toString(),
      );

  /// Display + the value stored in free-text fields: "Name (CODE)".
  String get label => (code == null || code!.isEmpty) ? name : '$name ($code)';

  @override
  bool operator ==(Object other) => other is EmployeeLookup && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

class EmployeeLookupRepository {
  EmployeeLookupRepository(this._api);
  final ApiClient _api;

  Future<List<EmployeeLookup>> search(String q) {
    return _api.get<List<EmployeeLookup>>(
      '/api/employees/lookup',
      query: {'q': q, 'page': 0, 'size': 20},
      parse: (d) {
        final content = (d is Map && d['content'] is List) ? d['content'] as List : const [];
        return content
            .whereType<Map<String, dynamic>>()
            .map(EmployeeLookup.fromJson)
            .toList();
      },
    );
  }
}

final employeeLookupRepositoryProvider = Provider<EmployeeLookupRepository>(
  (ref) => EmployeeLookupRepository(ref.watch(apiClientProvider)),
);

/// Search results for a query (empty/short query → empty list).
final employeeLookupProvider =
    FutureProvider.autoDispose.family<List<EmployeeLookup>, String>((ref, q) async {
  if (q.trim().length < 2) return const [];
  return ref.watch(employeeLookupRepositoryProvider).search(q.trim());
});
