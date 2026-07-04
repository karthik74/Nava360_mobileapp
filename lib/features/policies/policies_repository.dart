import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'policies_models.dart';

final policiesRepositoryProvider =
    Provider((ref) => PoliciesRepository(ref.watch(apiClientProvider)));

class PoliciesRepository {
  PoliciesRepository(this._api);
  final ApiClient _api;

  /// Policies applicable to the signed-in employee (current published versions).
  Future<List<MyPolicy>> myPolicies() {
    return _api.get<List<MyPolicy>>(
      '/api/policies/my',
      parse: (d) => ((d as List?) ?? const [])
          .map((e) => MyPolicy.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Record a version-specific acknowledgement (idempotent server-side).
  Future<void> acknowledge(int policyId, int versionId) {
    return _api.post<void>(
      '/api/policies/$policyId/versions/$versionId/acknowledge',
      parse: (_) {},
    );
  }

  /// The policy PDF bytes, fetched through the authenticated endpoint (which
  /// enforces applicability). Rendered in-app, view-only.
  Future<Uint8List> fetchPdf(int policyId, int versionId) {
    return _api.getBytes('/api/policies/$policyId/versions/$versionId/file');
  }
}
