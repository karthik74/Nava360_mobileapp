import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../auth/auth_controller.dart';
import 'requisition_models.dart';

class RequisitionRepository {
  RequisitionRepository(this._api);
  final ApiClient _api;

  /// Requisitions created by the current user (paged endpoint — first page).
  Future<List<RequisitionSummary>> listMine() {
    return _api.get<List<RequisitionSummary>>(
      '/api/requisitions/my',
      query: {'size': 50, 'sort': 'updatedAt,desc'},
      parse: (d) {
        final map = (d as Map<String, dynamic>?) ?? const {};
        final content = (map['content'] as List?) ?? const [];
        return content
            .map((e) => RequisitionSummary.fromJson(e as Map<String, dynamic>))
            .toList();
      },
    );
  }

  /// Creates a new requisition (starts in DRAFT). Requires REQUISITION_CREATE.
  Future<void> create(NewRequisition req) {
    return _api.post<void>(
      '/api/requisitions',
      body: req.toJson(),
      parse: (_) {},
    );
  }

  /// All branches with their org hierarchy (region/division/area).
  Future<List<BranchOption>> listBranches() {
    return _api.get<List<BranchOption>>(
      '/api/org/branches',
      parse: (d) {
        final list = (d as List?) ?? const [];
        return list
            .map((e) => BranchOption.fromJson(e as Map<String, dynamic>))
            .toList();
      },
    );
  }
}

final requisitionRepositoryProvider = Provider<RequisitionRepository>(
  (ref) => RequisitionRepository(ref.watch(apiClientProvider)),
);

/// "My requisitions" list — auto-disposes so it refetches when revisited.
final myRequisitionsProvider =
    FutureProvider.autoDispose<List<RequisitionSummary>>((ref) {
  return ref.watch(requisitionRepositoryProvider).listMine();
});

/// Branches the current user may select — filtered to the user's scoped
/// `branchIds`. An empty scope means no restriction, so all (active) branches
/// are returned. Sorted by region → division → area → branch for the dropdown.
final scopedBranchesProvider =
    FutureProvider.autoDispose<List<BranchOption>>((ref) async {
  final all = await ref.watch(requisitionRepositoryProvider).listBranches();
  final scope = ref.watch(authUserProvider)?.branchIds ?? const <int>{};
  var branches = all.where((b) => b.active).toList();
  if (scope.isNotEmpty) {
    branches = branches.where((b) => scope.contains(b.id)).toList();
  }
  branches.sort((a, b) {
    final byHierarchy = a.hierarchy.compareTo(b.hierarchy);
    return byHierarchy != 0 ? byHierarchy : a.label.compareTo(b.label);
  });
  return branches;
});
