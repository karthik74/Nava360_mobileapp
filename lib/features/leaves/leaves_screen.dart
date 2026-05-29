import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'leave_models.dart';
import 'leave_repository.dart';

final _myLeavesProvider = FutureProvider.autoDispose<List<LeaveRequest>>((ref) {
  final user = ref.watch(authUserProvider);
  if (user?.employeeId == null) return Future.value([]);
  return ref.watch(leaveRepositoryProvider).listForEmployee(user!.employeeId!);
});

final _myBalanceProvider =
    FutureProvider.autoDispose<EmployeeLeaveBalances?>((ref) {
  final user = ref.watch(authUserProvider);
  if (user?.employeeId == null) return Future.value(null);
  return ref.watch(leaveRepositoryProvider).getBalance(user!.employeeId!);
});

class LeavesScreen extends ConsumerWidget {
  const LeavesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(_myBalanceProvider);
    final leaves = ref.watch(_myLeavesProvider);

    final mq = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: Padding(
        padding: EdgeInsets.only(
          bottom: mq.padding.bottom + AppChrome.bottomNavHeight + 8,
        ),
        child: _NewRequestFab(
          onTap: () => _openRequest(context, ref),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: Colors.white.withOpacity(0.85),
        onRefresh: () async {
          ref.invalidate(_myBalanceProvider);
          ref.invalidate(_myLeavesProvider);
        },
        child: ListView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: EdgeInsets.fromLTRB(
            16,
            mq.padding.top + 5,
            16,
            mq.padding.bottom + AppChrome.bottomNavHeight + 84,
          ),
          children: [
            const AppSectionHeader(
              title: 'Leave balance',
              subtitle: 'Days available for each category',
            ),
            const SizedBox(height: 12),
            balance.when(
              data: (b) {
                if (b == null || b.balances.isEmpty) {
                  return const AppEmptyState(
                    icon: Icons.beach_access_rounded,
                    message: 'No balance configured yet.',
                  );
                }
                return SizedBox(
                  height: 108,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: b.balances.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => _BalanceCard(b: b.balances[i]),
                  ),
                );
              },
              loading: () => const AppLoadingBlock(height: 130),
              error: (e, _) => AppErrorPanel(
                message: e.toString(),
                onRetry: () => ref.invalidate(_myBalanceProvider),
              ),
            ),
            const SizedBox(height: 28),
            const AppSectionHeader(
              title: 'My requests',
              subtitle: 'Track the status of your leaves',
            ),
            const SizedBox(height: 12),
            leaves.when(
              data: (rows) {
                if (rows.isEmpty) {
                  return const AppEmptyState(
                    icon: Icons.event_note_rounded,
                    message: 'No leave requests yet. Tap + to create one.',
                  );
                }
                return Column(
                  children: [
                    for (final r in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _LeaveTile(r: r),
                      ),
                  ],
                );
              },
              loading: () => const AppLoadingBlock(height: 130),
              error: (e, _) => AppErrorPanel(
                message: e.toString(),
                onRetry: () => ref.invalidate(_myLeavesProvider),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openRequest(BuildContext context, WidgetRef ref) async {
    final user = ref.read(authUserProvider);
    if (user?.employeeId == null) return;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RequestSheet(employeeId: user!.employeeId!),
    );
    if (result == true) {
      ref.invalidate(_myLeavesProvider);
      ref.invalidate(_myBalanceProvider);
    }
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.b});
  final LeaveBalance b;

  static const _palettes = <Gradient>[
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
    ),
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF10B981), Color(0xFF34D399)],
    ),
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)],
    ),
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFEC4899), Color(0xFFF472B6)],
    ),
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF3B82F6), Color(0xFF60A5FA)],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final idx = b.leaveTypeLabel.hashCode.abs() % _palettes.length;
    final gradient = _palettes[idx];
    final balanceText = b.balanceDays == null ? '∞' : '${b.balanceDays}';
    final allowanceText = b.allowanceDays == null ? '∞' : '${b.allowanceDays}';

    return Container(
      width: 168,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: [
          BoxShadow(
            color: (gradient.colors.first).withOpacity(0.28),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(
                  Icons.calendar_month_rounded,
                  color: Colors.white,
                  size: 14,
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  b.leaveTypeLabel.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                balanceText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  height: 1,
                ),
              ),
              const SizedBox(width: 3),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  'days',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${b.usedDays} used · $allowanceText total',
            style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaveTile extends StatelessWidget {
  const _LeaveTile({required this.r});
  final LeaveRequest r;

  @override
  Widget build(BuildContext context) {
    final tone = StatusTone.forLeave(r.status);
    return GlassCard(
      padding: const EdgeInsets.all(14),
      shadow: AppShadows.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: tone.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: tone.color.withOpacity(0.22)),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.beach_access_rounded,
                    color: tone.color, size: 17),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _humanType(r.leaveType),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${r.numberOfDays ?? "?"} day(s) · ${r.fromDate} → ${r.toDate}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              StatusPill(label: tone.label, color: tone.color),
            ],
          ),
          if (r.reason != null && r.reason!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.45),
                borderRadius: BorderRadius.circular(AppRadii.sm),
                border: Border.all(color: Colors.white.withOpacity(0.55)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.format_quote_rounded,
                      size: 13, color: AppColors.muted),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      r.reason!,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.inkSoft,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _humanType(String t) {
    final s = t.toLowerCase().replaceAll('_', ' ');
    return s[0].toUpperCase() + s.substring(1) + ' leave';
  }
}

class _NewRequestFab extends StatelessWidget {
  const _NewRequestFab({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          gradient: AppColors.heroGradient,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.40),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, color: Colors.white, size: 18),
            SizedBox(width: 5),
            Text(
              'New request',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestSheet extends ConsumerStatefulWidget {
  const _RequestSheet({required this.employeeId});
  final int employeeId;

  @override
  ConsumerState<_RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends ConsumerState<_RequestSheet> {
  String _type = 'CASUAL';
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();
  final _reason = TextEditingController();
  bool _submitting = false;
  String? _err;

  static const _types = [
    ('CASUAL', Icons.coffee_rounded),
    ('SICK', Icons.medical_services_rounded),
    ('EARNED', Icons.beach_access_rounded),
    ('MATERNITY', Icons.child_friendly_rounded),
    ('PATERNITY', Icons.family_restroom_rounded),
    ('UNPAID', Icons.savings_rounded),
  ];

  Future<void> _pick({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: AppColors.ink,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = picked;
      }
    });
  }

  Future<void> _submit() async {
    if (_reason.text.trim().isEmpty) {
      setState(() => _err = 'Please enter a reason.');
      return;
    }
    setState(() {
      _submitting = true;
      _err = null;
    });
    try {
      await ref.read(leaveRepositoryProvider).create(LeaveCreateRequest(
            employeeId: widget.employeeId,
            leaveType: _type,
            fromDate: DateFormat('yyyy-MM-dd').format(_from),
            toDate: DateFormat('yyyy-MM-dd').format(_to),
            reason: _reason.text.trim(),
          ));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('EEE, d MMM y');
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.86),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.7), width: 1),
        ),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          const SizedBox(height: 20),
          const Text(
            'Request leave',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Pick a category and dates that work for you.',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Type',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in _types)
                _TypeChip(
                  label: t.$1,
                  icon: t.$2,
                  selected: _type == t.$1,
                  onTap: () => setState(() => _type = t.$1),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _DateField(
                  label: 'From',
                  value: df.format(_from),
                  onTap: () => _pick(isFrom: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DateField(
                  label: 'To',
                  value: df.format(_to),
                  onTap: () => _pick(isFrom: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Reason',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _reason,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Why are you taking these days?',
            ),
          ),
          if (_err != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.08),
                borderRadius: BorderRadius.circular(AppRadii.sm),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 16, color: AppColors.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _err!,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          Container(
            decoration: BoxDecoration(
              gradient: AppColors.heroGradient,
              borderRadius: BorderRadius.circular(AppRadii.md),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _submitting ? null : _submit,
                borderRadius: BorderRadius.circular(AppRadii.md),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  alignment: Alignment.center,
                  child: _submitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Text(
                          'Submit request',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withOpacity(0.10) : AppColors.bg,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.hairline,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? AppColors.primary : AppColors.inkSoft,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.primary : AppColors.inkSoft,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded,
                size: 16, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
