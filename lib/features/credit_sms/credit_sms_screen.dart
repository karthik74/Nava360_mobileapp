import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'credit_sms_models.dart';
import 'credit_sms_repository.dart';
import 'credit_sms_sync.dart';

/// Employee's "Credits detected" list. Shows each detected credit with its
/// amount, bank, sync/review status, and date. Pull to refresh also drains the
/// local outbox so anything captured offline is pushed.
class CreditSmsScreen extends ConsumerWidget {
  const CreditSmsScreen({super.key});

  static final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creditsAsync = ref.watch(myCreditsProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Detected Credits')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await ref.read(creditSmsServiceProvider).flush();
            ref.invalidate(myCreditsProvider);
            await ref.read(myCreditsProvider.future);
          },
          child: creditsAsync.when(
            loading: () => ListView(
              padding: const EdgeInsets.all(16),
              children: const [AppLoadingBlock(height: 200)],
            ),
            error: (e, _) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                AppErrorPanel(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(myCreditsProvider),
                ),
              ],
            ),
            data: (credits) => credits.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(16),
                    children: const [
                      AppEmptyState(
                        icon: Icons.inbox_rounded,
                        message:
                            'No credits detected yet. Bank credit SMS will appear here once received.',
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: credits.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _CreditTile(credits[i], _money),
                  ),
          ),
        ),
      ),
    );
  }
}

class _CreditTile extends StatelessWidget {
  const _CreditTile(this.credit, this.money);
  final CreditSms credit;
  final NumberFormat money;

  Color get _riskColor {
    switch (credit.riskLevel) {
      case 'HIGH':
        return AppColors.danger;
      case 'MEDIUM':
        return AppColors.warning;
      default:
        return AppColors.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = credit.detectedAmount == null
        ? '—'
        : money.format(credit.detectedAmount);
    final when = credit.smsReceivedAt ?? credit.createdAt;
    final whenText = when == null ? '' : _fmtDate(when);

    return GlassCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _riskColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: _riskColor.withOpacity(0.22)),
            ),
            child: Icon(Icons.south_west_rounded, color: _riskColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  amount,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (credit.bankName != null) credit.bankName!,
                    if (credit.referenceNo != null) 'Ref ${credit.referenceNo}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.muted),
                ),
                if (whenText.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(whenText,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.muted)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _StatusChip(label: credit.reviewLabel, color: _riskColor),
        ],
      ),
    );
  }

  String _fmtDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return DateFormat('dd MMM, hh:mm a').format(dt.toLocal());
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
