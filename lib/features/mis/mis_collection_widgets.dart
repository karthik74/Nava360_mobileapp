// ─────────────────────────────────────────────────────────────────────────────
//  Collection presentation components. Ports CollectionCards, BucketMatrixTable,
//  CollectionModeTable and CollectionUnitTable from the web MIS module.
//
//  Both metrics come from the SAME /collection/summary payload — counts from
//  demand_count / collection_count, rupees from demand_amt / collection_amt — so
//  the Accounts/Amount switch never costs an extra request.
//
//  Also hosts the small "deep hero" helpers the MIS drill screens (Collection,
//  Hourly, Disbursement, Portfolio) share: title + drill path, typed segmented
//  switch, chips, the lifted picker shell and the Regular headline stats.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import 'mis_charts.dart';
import 'mis_format.dart';
import 'mis_matrix_table.dart';
import 'mis_models.dart';
import 'mis_widgets.dart';

String _fmt(MisMetric m, double v) =>
    m == MisMetric.amount ? misRupees(v) : misNum(v);

/// Collection-% tone for the deep hero (lime / amber / soft red), using the
/// same 99 / 95 thresholds as [misPctColor].
Color _deepTone(double collection, double demand) {
  if (demand == 0) return Colors.white54;
  final p = collection / demand * 100;
  return p >= 99
      ? AppColors.live
      : p >= 95
          ? const Color(0xFFF2B347)
          : const Color(0xFFFF8A80);
}

// ── Deep hero helpers ────────────────────────────────────────────────────────

/// Hero title block for the MIS drill screens: large title, optional subtitle
/// and the tappable drill path underneath. Pass as `ProHero(titleWidget: …)`.
class MisDeepTitle extends StatelessWidget {
  const MisDeepTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.crumbs = const [],
  });

  final String title;
  final String? subtitle;
  final List<MisCrumb> crumbs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 24,
            height: 1.2,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.65,
            color: Colors.white,
          ),
        ),
        if (subtitle != null && subtitle!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle!,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: Colors.white70,
              ),
            ),
          ),
        if (crumbs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: MisDeepCrumbs(crumbs: crumbs),
          ),
      ],
    );
  }
}

/// Drill breadcrumb on a deep surface: earlier levels are underlined links,
/// the current level is plain white.
class MisDeepCrumbs extends StatelessWidget {
  const MisDeepCrumbs({super.key, required this.crumbs});
  final List<MisCrumb> crumbs;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < crumbs.length; i++) {
      final c = crumbs[i];
      final last = i == crumbs.length - 1;
      if (i > 0) {
        children.add(const Icon(Icons.chevron_right_rounded,
            size: 14, color: Colors.white38));
      }
      if (last || c.onTap == null) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Text(
            c.label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: last ? FontWeight.w600 : FontWeight.w500,
              color: last ? Colors.white : Colors.white70,
            ),
          ),
        ));
      } else {
        children.add(GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            c.onTap!();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: Text(
              c.label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: Color(0xC2FFFFFF),
                decoration: TextDecoration.underline,
                decorationColor: Color(0x47FFFFFF),
              ),
            ),
          ),
        ));
      }
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}

/// [ProHeroSegmented] over typed `(value, label)` options.
class MisDeepSegmented<T> extends StatelessWidget {
  const MisDeepSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final i = options.indexWhere((o) => o.$1 == value);
    return ProHeroSegmented(
      labels: [for (final o in options) o.$2],
      selected: i < 0 ? 0 : i,
      onChanged: (i) => onChanged(options[i].$1),
    );
  }
}

/// A pill for chip rows on the deep hero (hours, quick dates). White when
/// selected; an optional lime dot marks a live item.
class MisDeepChip extends StatelessWidget {
  const MisDeepChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.live = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(
            color:
                selected ? Colors.white : Colors.white.withValues(alpha: 0.14),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (live) ...[
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                    color: AppColors.live, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.deep : const Color(0xCCFFFFFF),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gives a light picker field the floating shadow it needs when it is passed
/// as `ProHero(overlap: …)`.
class MisLiftedField extends StatelessWidget {
  const MisLiftedField({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.md),
        boxShadow: AppShadows.lifted,
      ),
      child: child,
    );
  }
}

/// Small label row on the deep hero, e.g. "Regular demand vs collection".
class MisDeepLabel extends StatelessWidget {
  const MisDeepLabel(this.text, {super.key, this.trailing});
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Color(0xBDFFFFFF),
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: Color(0x94FFFFFF),
            ),
          ),
      ],
    );
  }
}

/// The Regular headline for the deep hero: Demand / Collection / FTOD /
/// Collection % with a progress track. Same figures as
/// [MisRegularCollectionCard] — the REGULAR bucket only, FTOD floored at zero.
/// [summary] may be null while it loads (values read "—").
class MisRegularHeroStats extends StatelessWidget {
  const MisRegularHeroStats({
    super.key,
    required this.summary,
    required this.metric,
    this.titleLabel,
  });

  final CollectionSummary? summary;
  final MisMetric metric;

  /// Title prefix. Null → 'Regular'; '' drops the prefix (Hourly).
  final String? titleLabel;

  @override
  Widget build(BuildContext context) {
    final has = summary != null;
    final reg = summary?.bucket('regular');
    final dem = reg?.demand(metric) ?? 0;
    final col = reg?.collection(metric) ?? 0;
    final ftod = (dem - col) < 0 ? 0.0 : dem - col;
    final ratio = dem > 0 ? (col / dem).clamp(0.0, 1.0) : 0.0;
    final tone = has ? _deepTone(col, dem) : Colors.white54;
    String v(double x) => has ? _fmt(metric, x) : '—';

    final prefix = titleLabel ?? 'Regular';
    final title = prefix.isEmpty
        ? 'Demand vs collection'
        : '$prefix demand vs collection';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        MisDeepLabel(title,
            trailing: metric == MisMetric.amount ? 'Amount' : 'Accounts'),
        const SizedBox(height: 8),
        ProHeroStats(stats: [
          ProStat(
            label: 'Demand',
            value: v(dem),
            sub: 'Regular bucket',
            dot: const Color(0xFFB8DDE5),
          ),
          ProStat(
            label: 'Collection',
            value: v(col),
            sub: 'Against demand',
            dot: const Color(0xFF6CBCCB),
          ),
        ]),
        const SizedBox(height: 8),
        ProHeroStats(stats: [
          ProStat(
            label: 'FTOD',
            value: v(ftod),
            sub: 'Demand still unpaid',
            dot: const Color(0xFFF2B347),
          ),
          ProStat(
            label: 'Collection %',
            value: has ? misPct2(col, dem) : '—',
            sub: 'of demand',
            dot: tone,
          ),
        ]),
        const SizedBox(height: 12),
        ProBar(
          value: ratio,
          color: tone,
          height: 5,
          track: Colors.white.withValues(alpha: 0.12),
        ),
      ],
    );
  }
}

// ── Regular Demand vs Collection ─────────────────────────────────────────────

/// The headline card: Demand / Collection / FTOD / Collection %, over a progress
/// track. Ports CollectionCards' first card.
///
/// Demand, Collection and FTOD are the REGULAR bucket ONLY, matching the live
/// site exactly. The 1-30 / 31-60 / PNPA buckets get their own rows in the DPD
/// table below; folding them into the headline gives a different, wrong figure.
class MisRegularCollectionCard extends StatelessWidget {
  const MisRegularCollectionCard({
    super.key,
    required this.summary,
    required this.metric,
    this.titleLabel,
  });

  final CollectionSummary summary;
  final MisMetric metric;

  /// Title prefix. Null → 'Regular' (the Collection screen). '' drops the
  /// prefix entirely — the Hourly screen's heading is just "Demand vs
  /// Collection (Accounts)", because its regular bucket is labelled
  /// "Regular as FTOD" elsewhere on that screen.
  final String? titleLabel;

  @override
  Widget build(BuildContext context) {
    final reg = summary.bucket('regular');
    final dem = reg?.demand(metric) ?? 0;
    final col = reg?.collection(metric) ?? 0;
    // FTOD is a SHORTFALL, so it floors at zero. Collection can legitimately
    // exceed demand — a borrower clearing arrears with the current instalment —
    // and the raw subtraction then renders a negative FTOD, which reads as a bug.
    final ftod = (dem - col) < 0 ? 0.0 : dem - col;
    final tone = misPctColor(col, dem);
    final ratio = dem > 0 ? (col / dem).clamp(0.0, 1.0) : 0.0;
    final prefix = titleLabel ?? 'Regular';

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProSectionHeader(
            title: prefix.isEmpty
                ? 'Demand vs collection'
                : '$prefix demand vs collection',
            subtitle: metric == MisMetric.amount ? 'Amount' : 'Accounts',
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _stat('Demand', _fmt(metric, dem))),
              Expanded(
                child: _stat('Collection', _fmt(metric, col),
                    color: AppColors.success),
              ),
              Expanded(
                child: _stat('FTOD', _fmt(metric, ftod),
                    color: AppColors.warning),
              ),
              Expanded(
                child:
                    _stat('Collection %', misPct2(col, dem), color: tone),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ProBar(value: ratio, color: tone, height: 6),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          alignment: Alignment.centerLeft,
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: color ?? AppColors.ink,
              letterSpacing: -0.3,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
      ],
    );
  }
}

// ── Shared section chrome ────────────────────────────────────────────────────

/// Grey explanatory line under a table.
class _Foot extends StatelessWidget {
  const _Foot(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
        child: Text(
          text,
          style: const TextStyle(
              fontSize: 12, height: 1.45, color: AppColors.muted),
        ),
      );
}

// ── DPD bucket matrix ────────────────────────────────────────────────────────

/// Book order for the row axis, matching the web.
const List<String> _bucketOrder = [
  'on_date',
  'regular',
  '1_30',
  '31_60',
  '61_90',
  'pnpa',
];

/// Bucket × measure matrix: one ROW per bucket (on-date → NPA, in book order),
/// columns Demand / Collection / Pending / Collection %. Ports BucketMatrixTable.
class MisBucketMatrix extends StatelessWidget {
  const MisBucketMatrix({
    super.key,
    required this.summary,
    required this.metric,
    this.regularLabel,
    this.regularShortLabel,
  });

  final CollectionSummary summary;
  final MisMetric metric;

  /// Override for the regular bucket's row name — the Hourly screen names it
  /// "Regular as FTOD" (the same figure IS the day's FTOD until the evening
  /// postings land). Null keeps the standard "Regular".
  final String? regularLabel;

  /// Short form used in the footnote's overlap sentence ("On-date overlaps
  /// FTOD"). Defaults to "Regular".
  final String? regularShortLabel;

  @override
  Widget build(BuildContext context) {
    final isAmount = metric == MisMetric.amount;
    final act = summary.action('activation');
    final clo = summary.action('closure');

    final rows = <MisMatrixRow>[];
    for (final name in _bucketOrder) {
      final b = summary.bucket(name);
      if (b == null) continue;
      rows.add(_row(
        key: name,
        label: name == 'regular' && regularLabel != null
            ? regularLabel!
            : misBucketLabel(name),
        note: name == 'on_date' ? misPrettyDate(summary.date) : null,
        demand: b.demand(metric),
        collection: b.collection(metric),
      ));
    }

    // NPA closes the table. Demand is a CASE COUNT and the schema has no NPA
    // demand amount, so in Amount mode Demand/Pending/Coll% are "—" rather than
    // a fabricated zero; Collection shows the recovered rupees.
    rows.add(_row(
      key: 'npa',
      label: misBucketLabel('npa'),
      note: isAmount ? 'recovery only' : null,
      demand: isAmount ? null : summary.npaCases,
      collection: (isAmount ? act?.amount : act?.accounts) ?? 0,
      accent: true,
    ));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProSectionHeader(
          title: 'DPD buckets',
          subtitle: isAmount ? 'Amount' : 'Accounts',
        ),
        const SizedBox(height: 10),
        if (isAmount && !summary.hasAmounts) ...[
          const ProNote(
            'No rupee amounts are stored for this date — every demand_amt / '
            'collection_amt is zero, so the figures below are blank for that '
            'reason, not because nothing was collected. The Daily Collection '
            "Report's OverAll sheet carries Demand/Collection as account counts "
            'only. Use Accounts for this date, or re-sync it from a report that '
            'includes the amount columns.',
            tone: ProNoteTone.warn,
          ),
          const SizedBox(height: 12),
        ],
        MisMatrixTable(
          stubHeader: 'Bucket',
          headers: const ['Demand', 'Collection', 'Pending', 'Collection %'],
          rows: rows,
        ),
        _Foot(
          isAmount
              ? 'NPA row shows recovered rupees only — the schema has no NPA '
                  'demand amount. Activation ${misRupees(act?.amount ?? 0)} · '
                  'Closure ${misRupees(clo?.amount ?? 0)}. On-date overlaps '
                  '${regularShortLabel ?? 'Regular'}, so the rows are not additive.'
              : 'NPA Demand is the open case count; Collection is activation '
                  'accounts. Activation ${misNum(act?.accounts ?? 0)} · '
                  'Closure ${misNum(clo?.accounts ?? 0)}. On-date overlaps '
                  '${regularShortLabel ?? 'Regular'}, so the rows are not additive.',
        ),
      ],
    );
  }

  MisMatrixRow _row({
    required String key,
    required String label,
    String? note,
    required double? demand,
    required double collection,
    bool accent = false,
  }) {
    // Pending is a shortfall — floored at zero for the same reason FTOD is.
    final pending = demand == null
        ? null
        : ((demand - collection) < 0 ? 0.0 : demand - collection);
    final hasPct = demand != null && demand > 0;
    final tone = hasPct ? misPctColor(collection, demand) : AppColors.muted;

    return MisMatrixRow(
      kind: accent ? MisRowKind.accent : MisRowKind.normal,
      lead: MisLead(label, note: note, chip: MisPalette.risk(key)),
      cells: [
        demand == null
            ? const MisCell.dash()
            : MisCell(_fmt(metric, demand)),
        MisCell(_fmt(metric, collection),
            color: AppColors.success, weight: FontWeight.w600),
        pending == null
            ? const MisCell.dash()
            : MisCell(_fmt(metric, pending)),
        MisCell(
          hasPct ? misPct2(collection, demand) : '—',
          color: tone,
          weight: FontWeight.w600,
          track: hasPct ? (collection / demand).clamp(0.0, 1.0) : null,
          trackColor: tone,
        ),
      ],
    );
  }
}

// ── Mode of Collection ───────────────────────────────────────────────────────

/// CollectionChannel value (as spelled in the report) → category. Note the
/// source spellings: the report writes MITHRAUPI and TRUCELL.
const Map<String, String> _channelCategory = {
  'TRUCELL': 'cash',
  'MITHRAUPI': 'digital',
  'DBQR': 'digital',
  'SBQR': 'digital',
  'ESAFOFFUS': 'digital',
  'ESAFSI': 'autopay',
  // Any channel missing from this map falls back to digital, so a new channel
  // is never silently dropped from the totals.
  'BRNET': 'digital',
};

const Map<String, String> _channelLabel = {
  'TRUCELL': 'Trucell',
  'MITHRAUPI': 'MithraUPI',
  'ESAFOFFUS': 'ESAFOFFUS',
  'ESAFSI': 'ESAFSI',
  'SBQR': 'SBQR',
  'DBQR': 'DBQR',
  'BRNET': 'BRNET',
};

const List<(String, String, Color)> _categoryMeta = [
  ('cash', 'Cash', AppColors.success),
  ('digital', 'Digital', AppColors.info),
  ('autopay', 'Autopay', AppColors.warning),
];

/// Share as a percentage. 1 dp normally; a small-but-real share gets a second
/// decimal so it never prints "0.0%" — a channel that took money did not take
/// none of it.
String _share(double part, double total) {
  if (total <= 0) return '—';
  final p = part / total * 100;
  if (p == 0) return '0.0%';
  return '${p.toStringAsFixed(p.abs() < 0.1 ? 2 : 1)}%';
}

/// How the day's collection split across payment channels, grouped into Cash /
/// Digital / Autopay. Each category is a bold row carrying its own subtotal with
/// every one of its channels indented beneath it.
///
/// TWO DIFFERENT PERCENTAGES, which is the point of the Share column:
///   category row → its share of the DAY'S TOTAL
///   channel row  → its share of ITS OWN CATEGORY
///
/// Live data only: with no channel feed for this date the panel renders NOTHING
/// rather than placeholder figures.
class MisCollectionModeTable extends StatelessWidget {
  const MisCollectionModeTable({super.key, required this.summary});

  final CollectionSummary summary;

  @override
  Widget build(BuildContext context) {
    if (summary.modes.isEmpty) return const SizedBox.shrink();

    // Fold the flat modes[] into the three categories, dropping empty ones.
    final buckets = <String, List<MisModeRow>>{
      'cash': [],
      'digital': [],
      'autopay': [],
    };
    for (final m in summary.modes) {
      if (m.channel.isEmpty) continue;
      final cat = _channelCategory[m.channel] ?? 'digital';
      buckets[cat]!.add(m);
    }
    final cats = [
      for (final c in _categoryMeta)
        if (buckets[c.$1]!.isNotEmpty)
          (
            key: c.$1,
            label: c.$2,
            color: c.$3,
            modes: buckets[c.$1]!
              ..sort((a, b) => b.amount.compareTo(a.amount)),
          ),
    ];
    if (cats.isEmpty) return const SizedBox.shrink();

    double catAcc(List<MisModeRow> m) =>
        m.fold<double>(0, (s, r) => s + r.accounts);
    double catAmt(List<MisModeRow> m) =>
        m.fold<double>(0, (s, r) => s + r.amount);

    final totalAcc = cats.fold<double>(0, (s, c) => s + catAcc(c.modes));
    final totalAmt = cats.fold<double>(0, (s, c) => s + catAmt(c.modes));

    final rows = <MisMatrixRow>[];
    for (final c in cats) {
      final cAcc = catAcc(c.modes);
      final cAmt = catAmt(c.modes);
      rows.add(
        MisMatrixRow(
          kind: MisRowKind.category,
          bgColor: c.color.withValues(alpha: 0.07),
          lead: MisLead(c.label, chip: c.color),
          cells: [
            MisCell(misNum(cAcc)),
            MisCell(misRupees(cAmt)),
            MisCell(
              _share(cAmt, totalAmt),
              color: c.color,
              weight: FontWeight.w600,
              track: cAmt > 0 ? (cAmt / totalAmt).clamp(0.0, 1.0) : 0,
              trackColor: c.color,
            ),
          ],
        ),
      );
      // Child rows: each mode in the category.
      for (final m in c.modes) {
        rows.add(MisMatrixRow(
          kind: MisRowKind.child,
          lead: MisLead(_channelLabel[m.channel] ?? m.channel, indent: true),
          cells: [
            MisCell(misNum(m.accounts)),
            MisCell(misRupees(m.amount)),
            // Against its OWN category, not the day. With one channel this is
            // 100%, which correctly reads as "Cash is entirely Trucell".
            MisCell(
              _share(m.amount, cAmt),
              muted: true,
              track: cAmt > 0 ? (m.amount / cAmt).clamp(0.0, 1.0) : 0,
              trackColor: c.color.withValues(alpha: 0.5),
            ),
          ],
        ));
      }
    }
    rows.add(MisMatrixRow(
      kind: MisRowKind.total,
      lead: const MisLead('Total'),
      cells: [
        MisCell(misNum(totalAcc)),
        MisCell(misRupees(totalAmt)),
        const MisCell('100.0%'),
      ],
    ));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ProSectionHeader(
          title: 'Mode of collection',
          subtitle: 'Share of the day’s collected amount',
        ),
        const SizedBox(height: 10),
        // The cash-vs-digital split is the headline question this panel answers,
        // and reading it off three table rows is slower than seeing it. One
        // segmented bar carries the whole answer; the table below is the detail.
        GlassCard(child: _splitBar(cats, catAmt, totalAmt)),
        const SizedBox(height: 12),
        MisMatrixTable(
          stubHeader: 'Mode',
          headers: const ['Accounts', 'Amount', 'Share'],
          rows: rows,
          stubWidth: 128,
        ),
        _Foot(
          'Share is by amount: a category is shown against the day’s total, '
          'a channel against its own category — so Digital’s channels add to '
          '100% of Digital, not of the day. Accounts are distinct loan accounts '
          'per channel; a client paying twice in a day counts once.'
          '${summary.modesAllProducts ? " Not affected by the product filter — the channel feed carries no product split." : ""}'
          '${summary.modesUnmappedAmount > 0 ? " ${misRupees(summary.modesUnmappedAmount)} from officers not matched to a branch is included in the all-India total but drops out when you drill in." : ""}',
        ),
      ],
    );
  }

  Widget _splitBar(
    List<({String key, String label, Color color, List<MisModeRow> modes})>
        cats,
    double Function(List<MisModeRow>) catAmt,
    double totalAmt,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProStackBar(
          height: 10,
          parts: [
            for (final c in cats)
              MapEntry(totalAmt > 0 ? catAmt(c.modes) : 1.0, c.color),
          ],
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < cats.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                    color: cats[i].color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(cats[i].label,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.inkSoft)),
              ),
              Text(misRupees(catAmt(cats[i].modes)),
                  style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.muted,
                      fontFeatures: [FontFeature.tabularFigures()])),
              const SizedBox(width: 10),
              SizedBox(
                width: 54,
                child: Text(
                  _share(catAmt(cats[i].modes), totalAmt),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: cats[i].color,
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ── Collection drill table ───────────────────────────────────────────────────

/// One ROW per unit at the current level: Unit | Demand | Collection | Balance |
/// Coll %, in the unit chosen by the screen's Accounts/Amount switch, with a
/// Total row. Ports CollectionUnitTable.
class MisCollectionUnitTable extends StatelessWidget {
  const MisCollectionUnitTable({
    super.key,
    required this.rows,
    required this.levelLabel,
    required this.metric,
    required this.unitOf,
    this.subOf,
    this.onRowTap,
    this.balanceLabel = 'Balance',
  });

  final List<CollectionRow> rows;
  final String levelLabel;
  final MisMetric metric;
  final String Function(CollectionRow) unitOf;
  final String? Function(CollectionRow)? subOf;
  final void Function(CollectionRow)? onRowTap;

  /// Header of the shortfall column — the Hourly screen names it "FTOD"
  /// (mirrors the web's balanceLabel="Regular as FTOD").
  final String balanceLabel;

  // The shortfall floors at zero: collection can legitimately exceed demand (a
  // borrower clearing arrears with the current instalment) and the raw
  // subtraction then prints a negative, which reads as a bug.
  static double _short(double d, double c) => (d - c) < 0 ? 0 : d - c;

  @override
  Widget build(BuildContext context) {
    // Percentages are computed from the SUMMED demand/collection, never averaged
    // across rows — a 10-account branch must not weigh the same as a 10,000-
    // account one.
    final totDem = rows.fold<double>(0, (s, r) => s + r.demand(metric));
    final totCol = rows.fold<double>(0, (s, r) => s + r.collection(metric));

    return MisMatrixTable(
      stubHeader: levelLabel,
      headers: ['Demand', 'Collection', balanceLabel, 'Coll %'],
      rows: [
        for (final r in rows) _row(r),
        if (rows.isNotEmpty)
          MisMatrixRow(
            kind: MisRowKind.total,
            lead: const MisLead('Total'),
            cells: [
              MisCell(_fmt(metric, totDem)),
              MisCell(_fmt(metric, totCol)),
              MisCell(_fmt(metric, _short(totDem, totCol))),
              MisCell(misPct2(totCol, totDem)),
            ],
          ),
      ],
    );
  }

  MisMatrixRow _row(CollectionRow r) {
    final d = r.demand(metric);
    final c = r.collection(metric);
    return MisMatrixRow(
      lead: MisLead(unitOf(r), note: subOf?.call(r)),
      onTap: onRowTap == null ? null : () => onRowTap!(r),
      cells: [
        MisCell(_fmt(metric, d)),
        MisCell(_fmt(metric, c),
            color: AppColors.success, weight: FontWeight.w600),
        MisCell(_fmt(metric, _short(d, c))),
        MisCell(
          misPct2(c, d),
          weight: FontWeight.w600,
          track: d > 0 ? (c / d).clamp(0.0, 1.0) : 0,
          trackColor: AppColors.primary,
        ),
      ],
    );
  }
}

// ── Scope chip ───────────────────────────────────────────────────────────────

/// "Regional Manager view" lock tag (for the deep hero). Every /collection/*
/// query is auto-scoped to the signed-in user's tier, so a region-tier user
/// sees ~1/5 of the all-India figures — which looks like wrong data next to an
/// unscoped screen. Say so plainly instead of leaving the reader to guess.
class MisScopeChip extends StatelessWidget {
  const MisScopeChip({super.key, required this.tier});
  final String tier;

  @override
  Widget build(BuildContext context) {
    return ProHeroTag(
      '${misTierLabel(tier)} view',
      tone: ProTagTone.warn,
      icon: Icons.lock_rounded,
    );
  }
}
