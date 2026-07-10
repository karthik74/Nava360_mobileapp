// Shared MIS presentation widgets — KPI cards, unit/metric cards, segmented
// pills, drill breadcrumb, dropdowns and a generic table. Reuses the app theme
// tokens so MIS matches nava360. Ports SnapshotCard / UnitCard /
// MetricColumnsCard / DataTable / ScopeFilter / DateSelect.

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'mis_format.dart';

/// Map a web accent name to a theme colour.
Color misAccent(String accent) {
  switch (accent) {
    case 'emerald':
      return AppColors.success;
    case 'sky':
      return AppColors.accent;
    case 'amber':
      return AppColors.warning;
    case 'red':
      return AppColors.danger;
    case 'indigo':
    default:
      return AppColors.primary;
  }
}

/// KPI "snapshot" card — icon chip + big value + label (+ optional sub).
class MisSnapshotCard extends StatelessWidget {
  const MisSnapshotCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accent = 'indigo',
    this.sub,
  });

  final String label;
  final String value;
  final IconData icon;
  final String accent;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final color = misAccent(accent);
    return GlassCard(
      padding: const EdgeInsets.all(13),
      shadow: AppShadows.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.22)),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 10),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                  letterSpacing: -0.3),
            ),
          ),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600)),
          if (sub != null && sub!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(sub!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
          ],
        ],
      ),
    );
  }
}

/// Lay out KPI cards responsively (default 3 across on a phone).
class MisSnapshotGrid extends StatelessWidget {
  const MisSnapshotGrid({super.key, required this.cards, this.perRow = 3});
  final List<Widget> cards;
  final int perRow;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      const gap = 10.0;
      final w = (c.maxWidth - gap * (perRow - 1)) / perRow;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final card in cards) SizedBox(width: w, child: card),
        ],
      );
    });
  }
}

/// A drill-grid unit card (collection): title, optional subtitle/parent,
/// demand + collection + coll% with a progress track.
class MisUnitCard extends StatelessWidget {
  const MisUnitCard({
    super.key,
    required this.title,
    this.subtitle,
    this.parent,
    required this.demand,
    required this.collection,
    this.money = false,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final String? parent;
  final double demand;
  final double collection;
  final bool money;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pct = demand > 0 ? (collection / demand) * 100 : 0.0;
    final tone = pct >= 99
        ? AppColors.success
        : pct >= 95
            ? AppColors.warning
            : AppColors.danger;
    String f(double v) => money ? misRupees(v) : misNum(v);

    return _MisTappableCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink)),
              ),
              if (onTap != null)
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.muted),
            ],
          ),
          if ((subtitle != null && subtitle!.isNotEmpty) ||
              (parent != null && parent!.isNotEmpty)) ...[
            const SizedBox(height: 1),
            Text(
              [subtitle, parent].where((s) => s != null && s.isNotEmpty).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _kv('Demand', f(demand))),
              Expanded(child: _kv('Collection', f(collection), color: tone)),
              _kv('Coll %', misPct(collection, demand), color: tone, right: true),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: AppColors.hairline,
              valueColor: AlwaysStoppedAnimation(tone),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String label, String value, {Color? color, bool right = false}) {
    return Column(
      crossAxisAlignment:
          right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
        const SizedBox(height: 1),
        Text(value,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color ?? AppColors.ink,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ],
    );
  }
}

/// A card with a title, optional subtitle + trailing badge, and 2-3 metric
/// columns (portfolio / disbursement).
class MisMetricColumnsCard extends StatelessWidget {
  const MisMetricColumnsCard({
    super.key,
    required this.title,
    required this.columns,
    this.subtitle,
    this.badge,
    this.accent = 'indigo',
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? badge;
  final String accent;
  final List<(String, String)> columns; // (label, value)
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = misAccent(accent);
    return _MisTappableCard(
      onTap: onTap,
      accentBar: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink)),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.muted)),
                    ],
                  ],
                ),
              ),
              if (badge != null) badge!,
              if (onTap != null && badge == null)
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.muted),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < columns.length; i++)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(columns[i].$1,
                          style: const TextStyle(
                              fontSize: 10.5, color: AppColors.muted)),
                      const SizedBox(height: 1),
                      Text(columns[i].$2,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                              fontFeatures: [FontFeature.tabularFigures()])),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MisTappableCard extends StatelessWidget {
  const _MisTappableCard({required this.child, this.onTap, this.accentBar});
  final Widget child;
  final VoidCallback? onTap;
  final Color? accentBar;

  @override
  Widget build(BuildContext context) {
    final content = GlassCard(
      padding: EdgeInsets.zero,
      shadow: AppShadows.soft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (accentBar != null)
            Container(width: 4, decoration: BoxDecoration(color: accentBar)),
          Expanded(
            child: Padding(padding: const EdgeInsets.all(13), child: child),
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

/// Segmented pill control (product / metric / tab toggles).
class MisSegmented<T> extends StatelessWidget {
  const MisSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });
  final List<(T, String)> options; // (value, label)
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in options)
            GestureDetector(
              onTap: () => onChanged(o.$1),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                decoration: BoxDecoration(
                  color: o.$1 == value ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Text(o.$2,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color:
                            o.$1 == value ? Colors.white : AppColors.muted)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Cards ↔ table view toggle.
class MisViewToggle extends StatelessWidget {
  const MisViewToggle({super.key, required this.table, required this.onChanged});
  final bool table;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, bool active, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: active ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Icon(icon,
                size: 16, color: active ? Colors.white : AppColors.muted),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(Icons.grid_view_rounded, !table, () => onChanged(false)),
          const SizedBox(width: 2),
          btn(Icons.table_rows_rounded, table, () => onChanged(true)),
        ],
      ),
    );
  }
}

/// Labelled dropdown used for date / month / parameter pickers.
class MisDropdown<T> extends StatelessWidget {
  const MisDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
  });
  final String? label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label!,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted)),
          const SizedBox(height: 4),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.hairline),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              isDense: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                  color: AppColors.muted),
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Date / month pickers (calendar; only dates that have data) ───────────────

const List<String> _monthsAbbr = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const List<String> _monthsFull = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// A dropdown-styled field that opens a modern Material calendar, restricted to
/// the [available] dates (only days that actually have data are selectable).
/// [value] and the emitted value are the original strings from [available].
class MisDatePicker extends StatelessWidget {
  const MisDatePicker({
    super.key,
    this.label,
    required this.value,
    required this.available,
    required this.onChanged,
  });
  final String? label;
  final String? value;
  final List<String> available;
  final ValueChanged<String> onChanged;

  static DateTime? _parse(String s) {
    final t = s.length >= 10 ? s.substring(0, 10) : s;
    final p = t.split('-');
    if (p.length < 3) return null;
    final y = int.tryParse(p[0]), m = int.tryParse(p[1]), d = int.tryParse(p[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  static String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _open(BuildContext context) async {
    final byKey = <String, String>{};
    final dates = <DateTime>[];
    for (final s in available) {
      final dt = _parse(s);
      if (dt != null) {
        byKey[_key(dt)] = s;
        dates.add(dt);
      }
    }
    if (dates.isEmpty) return;
    dates.sort();
    final sel = value != null ? _parse(value!) : null;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      // A 6-week month makes the grid taller than the default sheet cap
      // (9/16 of screen), which clips the last row / overflows. Let the
      // sheet size to its content instead.
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _MisCalendarSheet(
        byKey: byKey,
        first: dates.first,
        last: dates.last,
        initialSelected:
            (sel != null && byKey.containsKey(_key(sel))) ? sel : null,
      ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return _MisPickerField(
      label: label,
      text: (value != null && value!.isNotEmpty)
          ? misPrettyDate(value)
          : 'Select date',
      icon: Icons.event_rounded,
      onTap: available.isEmpty ? null : () => _open(context),
    );
  }
}

/// A dropdown-styled field that opens a modern month grid (year sections; only
/// months present in [available] are selectable). Values are month anchors
/// ("YYYY-MM-01" or "YYYY-MM").
class MisMonthPicker extends StatelessWidget {
  const MisMonthPicker({
    super.key,
    this.label,
    required this.value,
    required this.available,
    required this.onChanged,
  });
  final String? label;
  final String? value;
  final List<String> available;
  final ValueChanged<String> onChanged;

  static (int, int)? _ym(String s) {
    final p = s.split('-');
    if (p.length < 2) return null;
    final y = int.tryParse(p[0]), m = int.tryParse(p[1]);
    if (y == null || m == null) return null;
    return (y, m);
  }

  Future<void> _open(BuildContext context) async {
    final byYear = <int, Set<int>>{};
    final orig = <String, String>{};
    for (final s in available) {
      final ym = _ym(s);
      if (ym != null) {
        byYear.putIfAbsent(ym.$1, () => <int>{}).add(ym.$2);
        orig['${ym.$1}-${ym.$2}'] = s;
      }
    }
    if (byYear.isEmpty) return;
    final years = byYear.keys.toList()..sort((a, b) => b.compareTo(a));
    final sel = value != null ? _ym(value!) : null;
    final selKey = sel != null ? '${sel.$1}-${sel.$2}' : null;

    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _MonthGridSheet(
        years: years,
        byYear: byYear,
        orig: orig,
        selectedKey: selKey,
      ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return _MisPickerField(
      label: label,
      text: (value != null && value!.isNotEmpty)
          ? misMonthLabel(value!)
          : 'Select month',
      icon: Icons.calendar_month_rounded,
      onTap: available.isEmpty ? null : () => _open(context),
    );
  }
}

class _MisPickerField extends StatelessWidget {
  const _MisPickerField({
    this.label,
    required this.text,
    required this.icon,
    required this.onTap,
  });
  final String? label;
  final String text;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label!,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted)),
          const SizedBox(height: 4),
        ],
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.md),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(text,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink)),
                  ),
                  const Icon(Icons.keyboard_arrow_down_rounded,
                      color: AppColors.muted),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MonthGridSheet extends StatelessWidget {
  const _MonthGridSheet({
    required this.years,
    required this.byYear,
    required this.orig,
    required this.selectedKey,
  });
  final List<int> years;
  final Map<int, Set<int>> byYear;
  final Map<String, String> orig;
  final String? selectedKey;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Select month',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink)),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final y in years) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 8),
                        child: Text('$y',
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.muted)),
                      ),
                      LayoutBuilder(builder: (context, c) {
                        const gap = 8.0;
                        final w = (c.maxWidth - gap * 3) / 4;
                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [
                            for (var m = 1; m <= 12; m++)
                              _monthChip(context, y, m, w),
                          ],
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _monthChip(BuildContext context, int year, int month, double width) {
    final enabled = byYear[year]?.contains(month) ?? false;
    final selected = selectedKey == '$year-$month';
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled
              ? () => Navigator.pop(context, orig['$year-$month'])
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primary
                  : enabled
                      ? AppColors.surfaceAlt
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(
                color: selected
                    ? AppColors.primary
                    : enabled
                        ? AppColors.hairline
                        : AppColors.hairline.withOpacity(0.4),
              ),
            ),
            child: Text(
              _monthsAbbr[month - 1],
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected
                    ? Colors.white
                    : enabled
                        ? AppColors.ink
                        : AppColors.muted.withOpacity(0.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom calendar sheet: available days show a green dot and are tappable,
/// unavailable days are greyed out, and a "Latest" button jumps to the most
/// recent (present) data date. Opens on the latest available month.
class _MisCalendarSheet extends StatefulWidget {
  const _MisCalendarSheet({
    required this.byKey,
    required this.first,
    required this.last,
    this.initialSelected,
  });
  final Map<String, String> byKey; // "yyyy-MM-dd" -> original string
  final DateTime first, last;
  final DateTime? initialSelected;

  @override
  State<_MisCalendarSheet> createState() => _MisCalendarSheetState();
}

class _MisCalendarSheetState extends State<_MisCalendarSheet> {
  late DateTime _visible; // first-of-month currently shown

  @override
  void initState() {
    super.initState();
    final base = widget.initialSelected ?? widget.last;
    _visible = DateTime(base.year, base.month);
  }

  static String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  int _mi(DateTime d) => d.year * 12 + d.month;
  bool get _canPrev =>
      _mi(_visible) > _mi(DateTime(widget.first.year, widget.first.month));
  bool get _canNext =>
      _mi(_visible) < _mi(DateTime(widget.last.year, widget.last.month));

  void _pop(String key) {
    final orig = widget.byKey[key];
    if (orig != null) Navigator.pop(context, orig);
  }

  @override
  Widget build(BuildContext context) {
    final y = _visible.year, m = _visible.month;
    final daysIn = DateTime(y, m + 1, 0).day;
    final firstWd = DateTime(y, m, 1).weekday % 7; // Sun = 0
    final sel = widget.initialSelected;

    final cells = <Widget>[];
    for (var i = 0; i < firstWd; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var d = 1; d <= daysIn; d++) {
      final key = _key(DateTime(y, m, d));
      final avail = widget.byKey.containsKey(key);
      final isSel = sel != null && sel.year == y && sel.month == m && sel.day == d;
      cells.add(_dayCell(d, avail, isSel, key));
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('${_monthsFull[m - 1]} $y',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink)),
                const Spacer(),
                IconButton(
                  onPressed: _canPrev
                      ? () => setState(
                          () => _visible = DateTime(y, m - 1))
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                IconButton(
                  onPressed: _canNext
                      ? () => setState(
                          () => _visible = DateTime(y, m + 1))
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                for (final w in const ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'])
                  Expanded(
                    child: Center(
                      child: Text(w,
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.muted)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 7,
              childAspectRatio: 1,
              children: cells,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                      color: AppColors.success, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                const Text('Data available',
                    style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: () => _pop(_key(widget.last)),
                  icon: const Icon(Icons.event_available_rounded, size: 18),
                  label: const Text('Latest'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayCell(int d, bool avail, bool isSel, String key) {
    if (isSel) {
      return InkWell(
        onTap: avail ? () => _pop(key) : null,
        customBorder: const CircleBorder(),
        child: Container(
          margin: const EdgeInsets.all(4),
          decoration:
              BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text('$d',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800)),
        ),
      );
    }
    if (!avail) {
      return Center(
        child: Text('$d',
            style: TextStyle(
                fontSize: 13, color: AppColors.muted.withOpacity(0.35))),
      );
    }
    return InkWell(
      onTap: () => _pop(key),
      customBorder: const CircleBorder(),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('$d',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink)),
          const SizedBox(height: 2),
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
                color: AppColors.success, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}

/// Drill breadcrumb: tap a crumb to reset to that level.
class MisCrumb {
  final String label;
  final VoidCallback? onTap;
  const MisCrumb(this.label, {this.onTap});
}

class MisBreadcrumb extends StatelessWidget {
  const MisBreadcrumb({super.key, required this.crumbs});
  final List<MisCrumb> crumbs;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < crumbs.length; i++) {
      if (i > 0) {
        children.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Icon(Icons.chevron_right_rounded,
              size: 15, color: AppColors.muted),
        ));
      }
      final c = crumbs[i];
      final last = i == crumbs.length - 1;
      children.add(GestureDetector(
        onTap: c.onTap,
        child: Text(
          c.label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: last ? FontWeight.w800 : FontWeight.w600,
            color: c.onTap != null && !last ? AppColors.primary : AppColors.ink,
          ),
        ),
      ));
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}

class MisSectionTitle extends StatelessWidget {
  const MisSectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text,
          style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.ink)),
    );
  }
}

// ── Generic table ────────────────────────────────────────────────────────────

class MisColumn<T> {
  final String header;
  final bool right;
  final Widget Function(T row) cell;
  const MisColumn(this.header, this.cell, {this.right = false});
}

class MisTable<T> extends StatelessWidget {
  const MisTable({
    super.key,
    required this.columns,
    required this.rows,
    this.onRowTap,
  });
  final List<MisColumn<T>> columns;
  final List<T> rows;
  final void Function(T row)? onRowTap;

  @override
  Widget build(BuildContext context) {
    Widget headerCell(MisColumn<T> c) => Expanded(
          flex: c.right ? 3 : 4,
          child: Text(
            c.header,
            textAlign: c.right ? TextAlign.right : TextAlign.left,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white),
          ),
        );

    Widget bodyCell(MisColumn<T> c, T row) => Expanded(
          flex: c.right ? 3 : 4,
          child: Align(
            alignment: c.right ? Alignment.centerRight : Alignment.centerLeft,
            child: DefaultTextStyle(
              style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.inkSoft,
                  fontWeight: FontWeight.w500,
                  fontFeatures: [FontFeature.tabularFigures()]),
              child: c.cell(row),
            ),
          ),
        );

    return GlassCard(
      padding: EdgeInsets.zero,
      shadow: AppShadows.soft,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Column(
          children: [
            Container(
              color: AppColors.primary,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [for (final c in columns) headerCell(c)]),
            ),
            for (var i = 0; i < rows.length; i++)
              InkWell(
                onTap: onRowTap == null ? null : () => onRowTap!(rows[i]),
                child: Container(
                  color: i.isOdd ? AppColors.surfaceAlt : AppColors.surface,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  child: Row(
                    children: [for (final c in columns) bodyCell(c, rows[i])],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shared empty/error/loading helpers for MIS sub-sections.
class MisInlineEmpty extends StatelessWidget {
  const MisInlineEmpty(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) =>
      AppEmptyState(icon: Icons.inbox_rounded, message: message);
}
