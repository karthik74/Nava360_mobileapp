import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'helpdesk_models.dart';
import 'helpdesk_repository.dart';

/// Helpdesk ticket lists — My Tickets + Assigned to Me tabs.
class HelpdeskTicketsScreen extends ConsumerWidget {
  const HelpdeskTicketsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: GlassBackdrop(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.ink,
            elevation: 0.5,
            title: const Text('Helpdesk'),
            bottom: const TabBar(tabs: [Tab(text: 'My Tickets'), Tab(text: 'Assigned')]),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => context.push('/helpdesk/raise'),
            icon: const Icon(Icons.add),
            label: const Text('Raise'),
          ),
          body: const TabBarView(children: [
            _TicketList(scope: 'mine'),
            _TicketList(scope: 'assigned'),
          ]),
        ),
      ),
    );
  }
}

class _TicketList extends ConsumerWidget {
  const _TicketList({required this.scope});
  final String scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(helpdeskTicketsProvider(scope));
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(helpdeskTicketsProvider(scope)),
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [
          Padding(padding: const EdgeInsets.all(24), child: AppErrorPanel(message: '$e')),
        ]),
        data: (rows) {
          if (rows.isEmpty) {
            return ListView(children: const [
              SizedBox(height: 80),
              AppEmptyState(icon: Icons.confirmation_number_outlined, message: 'No tickets here yet.'),
            ]);
          }
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _TicketCard(t: rows[i]),
          );
        },
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.t});
  final HdTicketSummary t;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(12),
      shadow: AppShadows.soft,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: () => context.push('/helpdesk/tickets/${t.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                ),
                helpdeskPriorityChip(t.priority),
              ],
            ),
            const SizedBox(height: 4),
            Text('${t.ticketNumber}${t.category != null ? " · ${t.category}" : ""}',
                style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
            const SizedBox(height: 8),
            Row(
              children: [
                helpdeskStatusChip(t.status),
                const Spacer(),
                Text(
                  t.updatedAt == null ? '' : DateFormat('d MMM, h:mm a').format(t.updatedAt!.toLocal()),
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared chips (reused by the detail screen) ──
Widget helpdeskStatusChip(String status) {
  Color c;
  switch (status) {
    case 'OPEN': c = AppColors.info; break;
    case 'IN_PROGRESS': c = AppColors.primary; break;
    case 'ON_HOLD': c = AppColors.warning; break;
    case 'RESOLVED': c = AppColors.success; break;
    case 'CLOSED': c = AppColors.muted; break;
    case 'CANCELLED': c = AppColors.danger; break;
    default: c = AppColors.primary;
  }
  return _chip(status.replaceAll('_', ' '), c);
}

Widget helpdeskPriorityChip(String priority) {
  Color c;
  switch (priority) {
    case 'CRITICAL': c = AppColors.danger; break;
    case 'HIGH': c = AppColors.warning; break;
    case 'MEDIUM': c = AppColors.info; break;
    default: c = AppColors.muted;
  }
  return _chip(priority, c);
}

Widget _chip(String label, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: c)),
    );
