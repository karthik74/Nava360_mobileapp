// ─────────────────────────────────────────────────────────────────────────────
//  FO Scorecard Performance — embeddable tab body.
//
//  A self-contained, pull-to-refresh scorecard for a specific employee, designed
//  to drop into the team employee-detail screen's TabBarView. Mirrors the
//  card-first layout of My Performance, keyed by employeeId.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'performance_body.dart';
import 'performance_models.dart';
import 'performance_repository.dart';
import 'performance_widgets.dart';

class PerformanceTabBody extends ConsumerStatefulWidget {
  const PerformanceTabBody({super.key, required this.employeeId});
  final int employeeId;

  @override
  ConsumerState<PerformanceTabBody> createState() => _PerformanceTabBodyState();
}

class _PerformanceTabBodyState extends ConsumerState<PerformanceTabBody> {
  PeriodOption? _selected;
  List<PeriodOption> _periods = const [];
  String? _lastSynced;

  @override
  Widget build(BuildContext context) {
    final q = EmployeePerfQuery(
      widget.employeeId,
      month: _selected?.month,
      year: _selected?.year,
    );

    ref.listen<AsyncValue<PerformanceDetail>>(
      employeePerformanceProvider(q),
      (prev, next) => next.whenData(_absorb),
    );

    final async = ref.watch(employeePerformanceProvider(q));
    final selectedForSelector = _selected ?? _periodFromAsync(async);
    final mq = MediaQuery.of(context);

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(employeePerformanceProvider(q)),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 14, 16, mq.padding.bottom + 24),
        children: [
          PerfMonthSelector(
            periods: _periods,
            selected: selectedForSelector,
            lastSyncedLabel: _lastSynced == null ? null : 'Synced $_lastSynced',
            onChanged: (p) => setState(() => _selected = p),
          ),
          const SizedBox(height: 12),
          async.when(
            loading: () => const AppLoadingBlock(height: 240),
            error: (e, _) => AppErrorPanel(
              message: e.toString(),
              onRetry: () => ref.invalidate(employeePerformanceProvider(q)),
            ),
            data: (detail) => PerformanceScorecardBody(
              detail: detail,
              selectedPeriod: selectedForSelector,
            ),
          ),
        ],
      ),
    );
  }

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
