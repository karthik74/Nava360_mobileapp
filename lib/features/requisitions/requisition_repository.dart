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

  /// Aggregated dashboard for the caller's hierarchy (branch-scoped) or org-wide
  /// for ADMIN/HR. One call powers the Summary view.
  Future<RequisitionDashboard> dashboard({String q = ''}) {
    return _api.get<RequisitionDashboard>(
      '/api/requisitions/summary',
      query: q.trim().isEmpty ? null : {'q': q.trim()},
      parse: (d) =>
          RequisitionDashboard.fromJson((d as Map).cast<String, dynamic>()),
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

  /// Active master-data options for a lookup category (e.g. departments,
  /// designations) from `GET /api/lookups/{category}`.
  Future<List<LookupOption>> listLookup(String category) {
    return _api.get<List<LookupOption>>(
      '/api/lookups/$category',
      query: {'activeOnly': true},
      parse: (d) {
        final list = (d as List?) ?? const [];
        return list
            .map((e) => LookupOption.fromJson(e as Map<String, dynamic>))
            .toList();
      },
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

/// Aggregated requisition dashboard for the Summary view.
final requisitionDashboardProvider =
    FutureProvider.autoDispose<RequisitionDashboard>((ref) {
  return ref.watch(requisitionRepositoryProvider).dashboard();
});

/// Active department master options for the New-requisition dropdown.
final departmentOptionsProvider =
    FutureProvider.autoDispose<List<LookupOption>>((ref) {
  return ref.watch(requisitionRepositoryProvider).listLookup('departments');
});

/// Active designation master options for the New-requisition dropdown.
final designationOptionsProvider =
    FutureProvider.autoDispose<List<LookupOption>>((ref) {
  return ref.watch(requisitionRepositoryProvider).listLookup('designations');
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
