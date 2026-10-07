// Shared MIS presentation widgets — KPI cards, unit/metric cards, segmented
// pills, drill breadcrumb, dropdowns and a generic table. Reuses the app theme
// tokens and the Pro component library so MIS matches nava360. Ports
// SnapshotCard / UnitCard / MetricColumnsCard / DataTable / ScopeFilter /
// DateSelect.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/pro_ui.dart';
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

/// Border of the light "pick" fields (dropdowns / date / month pickers).
const Color _pickBorder = Color(0xFFDBE3E5);

/// KPI "snapshot" card — icon well + big value + label (+ optional sub).
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
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProIconWell(icon: icon, color: color, size: 32),
          const SizedBox(height: 10),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 19,
                height: 1.25,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.4,
                color: AppColors.ink,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 12, height: 1.3, color: AppColors.muted),
          ),
          if (sub != null && sub!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              sub!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.faint,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
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
      const gap = 8.0;
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
    this.footer,
  });

  final String title;
  final String? subtitle;
  final String? parent;
  final double demand;
  final double collection;
  final bool money;
  final VoidCallback? onTap;

  /// Optional extra content below the metrics (e.g. an intra-day sparkline).
  final Widget? footer;

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
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.33,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.15,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (onTap != null)
                const Icon(Icons.chevron_right_rounded,
                    size: 20, color: Color(0xFFB3C0C3)),
            ],
          ),
          if ((subtitle != null && subtitle!.isNotEmpty) ||
              (parent != null && parent!.isNotEmpty))
            Text(
              [subtitle, parent]
                  .where((s) => s != null && s.isNotEmpty)
                  .join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption,
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _kv('Demand', f(demand))),
              Expanded(child: _kv('Collection', f(collection), color: tone)),
              _kv('Coll %', misPct(collection, demand),
                  color: tone, right: true),
            ],
          ),
          const SizedBox(height: 10),
          ProBar(value: (pct / 100).clamp(0.0, 1.0), color: tone, height: 4),
          if (footer != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.hairlineSoft),
            const SizedBox(height: 10),
            footer!,
          ],
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
            style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
        const SizedBox(height: 1),
        Text(
          value,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: color ?? AppColors.ink,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.33,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.15,
                        color: AppColors.ink,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption,
                      ),
                  ],
                ),
              ),
              if (badge != null) badge!,
              if (onTap != null && badge == null)
                const Icon(Icons.chevron_right_rounded,
                    size: 20, color: Color(0xFFB3C0C3)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < columns.length; i++)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(columns[i].$1,
                          style: const TextStyle(
                              fontSize: 11.5, color: AppColors.muted)),
                      const SizedBox(height: 1),
                      Text(
                        columns[i].$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
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
  const _MisTappableCard({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = GlassCard(
      padding: const EdgeInsets.all(14),
      child: child,
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

/// Segmented control (product / metric / tab toggles) — a soft grey track with
/// the selected option lifted onto a white pill. Sizes to its content, so it
/// can sit inside a horizontal scroll view.
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
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.neutralTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in options)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(o.$1);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: o.$1 == value ? AppColors.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: o.$1 == value
                      ? const [
                          BoxShadow(
                            color: Color(0x240B1D21),
                            blurRadius: 2,
                            offset: Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  o.$2,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: o.$1 == value ? AppColors.ink : AppColors.muted,
                  ),
                ),
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
    Widget btn(IconData icon, bool active, String tip, VoidCallback onTap) =>
        Tooltip(
          message: tip,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? AppColors.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                boxShadow: active
                    ? const [
                        BoxShadow(
                          color: Color(0x240B1D21),
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: Icon(icon,
                  size: 18, color: active ? AppColors.ink : AppColors.muted),
            ),
          ),
        );
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.neutralTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(Icons.view_agenda_outlined, !table, 'One day at a time',
              () => onChanged(false)),
          const SizedBox(width: 2),
          btn(Icons.table_rows_rounded, table, 'Whole month table',
              () => onChanged(true)),
        ],
      ),
    );
  }
}

/// The light "pick" field: a 54px white box with a small grey label above the
/// value, an optional leading icon and a chevron. Opens whatever [onTap] does
/// (a sheet, a calendar, a checklist). Disabled (greyed) when [onTap] is null.
class MisPickField extends StatelessWidget {
  const MisPickField({
    super.key,
    this.label,
    required this.value,
    this.icon,
    this.onTap,
  });

  final String? label;
  final String value;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        side: const BorderSide(color: _pickBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: label == null ? 48 : 54),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 7, 10, 7),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon,
                      size: 18,
                      color: enabled ? AppColors.primary : AppColors.faint),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (label != null) _PickLabel(label!),
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.38,
                          fontWeight: FontWeight.w600,
                          color: enabled ? AppColors.ink : AppColors.faint,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.keyboard_arrow_down_rounded,
                    size: 20, color: AppColors.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PickLabel extends StatelessWidget {
  const _PickLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 12,
          height: 1.33,
          fontWeight: FontWeight.w500,
          color: AppColors.muted,
        ),
      );
}

/// Labelled dropdown used for date / month / parameter pickers. Same look as
/// [MisPickField]: the label sits inside the box, above the selected value.
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
    return Container(
      constraints: BoxConstraints(minHeight: label == null ? 48 : 54),
      padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: _pickBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          itemHeight: null,
          focusColor: Colors.transparent,
          dropdownColor: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.md),
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              size: 20, color: AppColors.faint),
          style: const TextStyle(
            fontFamily: 'Geist',
            fontSize: 14.5,
            fontWeight: FontWeight.w500,
            color: AppColors.ink,
          ),
          // The closed field shows the label above the chosen value; the open
          // menu keeps the plain items.
          selectedItemBuilder: (context) => [
            for (final item in items)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (label != null) _PickLabel(label!),
                  DefaultTextStyle.merge(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      height: 1.38,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                    child: item.child,
                  ),
                ],
              ),
          ],
          items: items,
          onChanged: onChanged,
        ),
      ),
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

/// White sheet chrome shared by the MIS pickers: radius 24 top + drag handle.
const ShapeBorder _sheetShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
);

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 40,
          height: 5,
          decoration: BoxDecoration(
            color: const Color(0xFFC6D3D6),
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      );
}

const TextStyle _sheetTitle = TextStyle(
  fontSize: 19,
  height: 1.3,
  fontWeight: FontWeight.w600,
  letterSpacing: -0.4,
  color: AppColors.ink,
);

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
      shape: _sheetShape,
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
    return MisPickField(
      label: label,
      value: (value != null && value!.isNotEmpty)
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
      shape: _sheetShape,
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
    return MisPickField(
      label: label,
      value: (value != null && value!.isNotEmpty)
          ? misMonthLabel(value!)
          : 'Select month',
      icon: label == null ? Icons.calendar_month_rounded : null,
      onTap: available.isEmpty ? null : () => _open(context),
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
            const _SheetHandle(),
            const SizedBox(height: 14),
            const Text('Select month', style: _sheetTitle),
            const SizedBox(height: 6),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final y in years) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 8),
                        child: Text('$y',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
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
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 44,
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
                        : AppColors.hairlineSoft,
              ),
            ),
            child: Text(
              _monthsAbbr[month - 1],
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected
                    ? Colors.white
                    : enabled
                        ? AppColors.ink
                        : AppColors.faint.withValues(alpha: 0.6),
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
            const _SheetHandle(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text('${_monthsFull[m - 1]} $y', style: _sheetTitle),
                ),
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: _canPrev
                      ? () => setState(
                          () => _visible = DateTime(y, m - 1))
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: _canNext
                      ? () => setState(
                          () => _visible = DateTime(y, m + 1))
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final w in const ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'])
                  Expanded(
                    child: Center(
                      child: Text(w,
                          style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
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
                const Text('Data available', style: AppText.caption),
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
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()])),
        ),
      );
    }
    if (!avail) {
      return Center(
        child: Text('$d',
            style: TextStyle(
                fontSize: 13.5, color: AppColors.faint.withValues(alpha: 0.55))),
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
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.ink,
                  fontFeatures: [FontFeature.tabularFigures()])),
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
          padding: EdgeInsets.symmetric(horizontal: 3),
          child: Icon(Icons.chevron_right_rounded,
              size: 16, color: AppColors.faint),
        ));
      }
      final c = crumbs[i];
      final last = i == crumbs.length - 1;
      final tappable = c.onTap != null && !last;
      children.add(GestureDetector(
        onTap: c.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            c.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: last ? FontWeight.w600 : FontWeight.w500,
              color: tappable ? AppColors.primary : AppColors.ink,
            ),
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
      padding: const EdgeInsets.only(left: 2, bottom: 10),
      child: Text(text, style: AppText.section),
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: c.right ? TextAlign.right : TextAlign.left,
            style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.muted),
          ),
        );

    Widget bodyCell(MisColumn<T> c, T row) => Expanded(
          flex: c.right ? 3 : 4,
          child: Align(
            alignment: c.right ? Alignment.centerRight : Alignment.centerLeft,
            child: DefaultTextStyle.merge(
              style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.inkSoft,
                  fontWeight: FontWeight.w500,
                  fontFeatures: [FontFeature.tabularFigures()]),
              child: c.cell(row),
            ),
          ),
        );

    return GlassCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Column(
          children: [
            Container(
              color: AppColors.surfaceAlt,
              constraints: const BoxConstraints(minHeight: 38),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [for (final c in columns) headerCell(c)]),
            ),
            for (var i = 0; i < rows.length; i++)
              Material(
                color: AppColors.surface,
                child: InkWell(
                  onTap: onRowTap == null ? null : () => onRowTap!(rows[i]),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    decoration: const BoxDecoration(
                      border: Border(
                          top: BorderSide(color: AppColors.hairlineSoft)),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    child: Row(
                      children: [for (final c in columns) bodyCell(c, rows[i])],
                    ),
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
