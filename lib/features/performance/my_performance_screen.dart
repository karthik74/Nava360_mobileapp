// ─────────────────────────────────────────────────────────────────────────────
//  FO Scorecard Performance — My Performance (self-service) screen.
//
//  Route: /my-performance. Card-first scorecard for the signed-in FO with a
//  sticky month selector, pull-to-refresh and graceful empty/error states.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'performance_body.dart';
import 'performance_models.dart';
import 'performance_repository.dart';
import 'performance_widgets.dart';

class MyPerformanceScreen extends ConsumerStatefulWidget {
  const MyPerformanceScreen({super.key});

  @override
  ConsumerState<MyPerformanceScreen> createState() =>
      _MyPerformanceScreenState();
}

class _MyPerformanceScreenState extends ConsumerState<MyPerformanceScreen> {
  /// The period the user has explicitly chosen (null ⇒ let the backend default
  /// to the latest available period).
  PeriodOption? _selected;

  /// Last-known period list + sync label, so the sticky selector stays stable
  /// while a newly-selected period is loading.
  List<PeriodOption> _periods = const [];
  String? _lastSynced;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider);
    final empId = user?.employeeId;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('My Performance')),
      body: empId == null
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: AppEmptyState(
                icon: Icons.insights_rounded,
                message:
                    'Your account isn\'t linked to an employee record, so there\'s no scorecard to show.',
              ),
            )
          : _buildBody(empId),
    );
  }

  Widget _buildBody(int empId) {
    final query = PerfQuery(month: _selected?.month, year: _selected?.year);

    // Capture period list / sync time / default selection as data arrives.
    ref.listen<AsyncValue<PerformanceDetail>>(
      myPerformanceProvider(query),
      (prev, next) {
        next.whenData(_absorb);
      },
    );

    final async = ref.watch(myPerformanceProvider(query));
    final selectedForSelector = _selected ?? _periodFromAsync(async);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: PerfMonthSelector(
            periods: _periods,
            selected: selectedForSelector,
            lastSyncedLabel:
                _lastSynced == null ? null : 'Synced $_lastSynced',
            onChanged: (p) => setState(() => _selected = p),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async =>
                ref.invalidate(myPerformanceProvider(query)),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                  16, 6, 16, MediaQuery.of(context).padding.bottom + 24),
              children: [
                async.when(
                  loading: () => const AppLoadingBlock(height: 240),
                  error: (e, _) => AppErrorPanel(
                    message: e.toString(),
                    onRetry: () =>
                        ref.invalidate(myPerformanceProvider(query)),
                  ),
                  data: (detail) => PerformanceScorecardBody(
                    detail: detail,
                    selectedPeriod: selectedForSelector,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Pull the period list / sync label out of a freshly-loaded detail, and pick
  /// a sensible default selection on first load.
  void _absorb(PerformanceDetail d) {
    final periods = d.availablePeriods;
    final summaryPeriod = (d.summary?.month != null && d.summary?.year != null)
        ? PeriodOption(
            month: d.summary!.month!,
            year: d.summary!.year!,
            label: d.summary!.monthLabel ?? '',
          )
        : null;
    final nextSelected = _selected ??
        (summaryPeriod != null && periods.contains(summaryPeriod)
            ? periods.firstWhere((p) => p == summaryPeriod)
            : (periods.isNotEmpty ? periods.first : summaryPeriod));

    final changed = !_listEquals(periods, _periods) ||
        d.lastSyncedAt != _lastSynced ||
        (_selected == null && nextSelected != null);
    if (!changed || !mounted) return;
    setState(() {
      _periods = periods;
      _lastSynced = d.lastSyncedAt;
      _selected ??= nextSelected;
    });
  }

  PeriodOption? _periodFromAsync(AsyncValue<PerformanceDetail> async) {
    final d = async.asData?.value;
    if (d?.summary?.month != null && d?.summary?.year != null) {
      return PeriodOption(
        month: d!.summary!.month!,
        year: d.summary!.year!,
        label: d.summary!.monthLabel ?? '',
      );
    }
    return _periods.isNotEmpty ? _periods.first : null;
  }

  bool _listEquals(List<PeriodOption> a, List<PeriodOption> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
