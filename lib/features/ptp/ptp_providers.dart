import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'ptp_models.dart';
import 'ptp_repository.dart';

/// Chip counts + scope for the PTP screen header.
final ptpSummaryProvider = FutureProvider.autoDispose<PtpSummary>(
  (ref) => ref.watch(ptpRepositoryProvider).summary(),
);

class PtpListState {
  final List<CrmPtp> items;
  final int page; // last page loaded
  final bool last;
  final bool loading; // first page in flight
  final bool loadingMore;
  // First-page failure: full-screen when nothing is loaded, else a 'could not
  // refresh' note above the rows still shown.
  final String? error;
  final String? moreError; // load-more failure (shown in the footer)

  const PtpListState({
    this.items = const [],
    this.page = -1,
    this.last = false,
    this.loading = true,
    this.loadingMore = false,
    this.error,
    this.moreError,
  });

  PtpListState copyWith({
    List<CrmPtp>? items,
    int? page,
    bool? last,
    bool? loading,
    bool? loadingMore,
    String? error,
    String? moreError,
  }) =>
      PtpListState(
        items: items ?? this.items,
        page: page ?? this.page,
        last: last ?? this.last,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        error: error,
        moreError: moreError,
      );
}

/// One paged list per filter chip. Auto-disposed when the chip is left, so
/// tapping a chip always re-queries fresh rows (a PTP moves between buckets
/// as days pass and syncs run).
class PtpListNotifier extends StateNotifier<PtpListState> {
  PtpListNotifier(this._repo, this.filter) : super(const PtpListState()) {
    refresh();
  }

  final PtpRepository _repo;
  final PtpFilter filter;

  // Bumped on every refresh so a slow page from before a pull-to-refresh can
  // never be appended to the fresh list.
  int _generation = 0;

  Future<void> refresh() async {
    final gen = ++_generation;
    state = state.copyWith(loading: true, loadingMore: false);
    try {
      final p = await _repo.mine(filter: filter, page: 0);
      if (!mounted || gen != _generation) return;
      state = PtpListState(items: p.items, page: p.page, last: p.last, loading: false);
    } catch (e) {
      if (!mounted || gen != _generation) return;
      state = state.copyWith(loading: false, error: _message(e));
    }
  }

  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || state.last) return;
    final gen = _generation;
    // copyWith clears error unless passed on: keep a failed refresh's error, so
    // the screen's 'Could not refresh' note does not vanish on a scroll.
    state = state.copyWith(loadingMore: true, error: state.error);
    try {
      final p = await _repo.mine(filter: filter, page: state.page + 1);
      if (!mounted || gen != _generation) return;
      // Rows can shift between pages while a sync runs; drop repeats by id.
      final seen = state.items.map((e) => e.id).toSet();
      state = state.copyWith(
        items: [...state.items, ...p.items.where((e) => seen.add(e.id))],
        page: p.page,
        last: p.last || p.items.isEmpty,
        loadingMore: false,
        error: state.error,
      );
    } catch (e) {
      if (!mounted || gen != _generation) return;
      state = state.copyWith(
          loadingMore: false, error: state.error, moreError: _message(e));
    }
  }

  static String _message(Object e) =>
      e is ApiException ? e.message : 'Could not load PTPs. Pull down to retry.';
}

final ptpListProvider = StateNotifierProvider.autoDispose
    .family<PtpListNotifier, PtpListState, PtpFilter>(
  (ref, filter) => PtpListNotifier(ref.watch(ptpRepositoryProvider), filter),
);
