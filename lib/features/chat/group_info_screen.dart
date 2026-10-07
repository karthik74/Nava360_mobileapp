import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../auth/auth_controller.dart';
import 'chat_controller.dart';
import 'chat_models.dart';
import 'chat_repository.dart';

class GroupInfoScreen extends ConsumerWidget {
  const GroupInfoScreen({super.key, required this.conversation});
  final Conversation conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider);
    final myEmpId = user?.employeeId;
    // Follow the live list copy so a rename / member change made here (or by
    // another admin) shows without leaving the screen.
    final conversation = ref
            .watch(conversationsProvider)
            .valueOrNull
            ?.where((c) => c.id == this.conversation.id)
            .firstOrNull ??
        this.conversation;
    final myMember = conversation.members
        .where((m) => m.employeeId == myEmpId)
        .firstOrNull;
    final isAdmin = myMember?.isAdmin ?? false;

    // Hero numbers from the member list already on the conversation.
    final memberN = conversation.members.length;
    final adminN = conversation.members.where((m) => m.isAdmin).length;
    final onlineN = conversation.members.where((m) => m.online).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Group info')),
      body: ProPage(
        hero: ProHero(
          overlap: ProKpiStrip(
            cells: [
              ProKpi(value: '$memberN', label: 'Members'),
              ProKpi(value: '$adminN', label: 'Admins'),
              ProKpi(
                value: '$onlineN',
                label: 'Online now',
                valueColor: onlineN > 0 ? AppColors.success : null,
              ),
            ],
          ),
          children: [
            ProHeroIdentity(
              name: conversation.title,
              role: 'Group chat · $memberN members',
              icon: Icons.group_rounded,
              tags: [
                if (isAdmin) const ProHeroTag('You are admin', tone: ProTagTone.ok),
                ProHeroTag('$adminN admin${adminN == 1 ? '' : 's'}'),
              ],
            ),
            ProLiveLine(
              text: onlineN == 0
                  ? 'Nobody in this group is online right now'
                  : '$onlineN of $memberN online now',
              color: onlineN == 0 ? Colors.white38 : AppColors.live,
            ),
            ProHeroActions(
              actions: [
                ProAction(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Open chat',
                  primary: true,
                  // Group info is only opened from its thread — back = chat.
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                if (isAdmin)
                  ProAction(
                    icon: Icons.edit_rounded,
                    label: 'Rename',
                    onTap: () => _rename(context, ref, conversation),
                  ),
                ProAction(
                  icon: Icons.exit_to_app_rounded,
                  label: 'Leave',
                  onTap: () => _confirmLeave(context, ref),
                ),
              ],
            ),
          ],
        ),
        children: [
          // Members section
          ProSectionHeader(
            title: 'Group participants · $memberN',
            small: true,
          ),
          ProListGroup(
            dividerIndent: 66,
            children: [
              for (final member in conversation.members)
                _MemberTile(
                  member: member,
                  isAdmin: isAdmin,
                  myEmployeeId: myEmpId,
                  conversationId: conversation.id,
                ),
            ],
          ),
          // Leave group — any member may leave, not just the creator/admins
          // (mirrors ChatPage.tsx on web). Delete is admin-only.
          ProListGroup(
            children: [
              _DangerRow(
                icon: Icons.exit_to_app_rounded,
                title: 'Leave group',
                subtitle: 'You will no longer receive its messages',
                onTap: () => _confirmLeave(context, ref),
              ),
              if (isAdmin)
                _DangerRow(
                  icon: Icons.delete_forever_rounded,
                  title: 'Delete group',
                  subtitle: 'Closes and hides the group for everyone',
                  onTap: () => _confirmDelete(context, ref, conversation),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static final _destructive = FilledButton.styleFrom(
    backgroundColor: AppColors.dangerTint,
    foregroundColor: AppColors.danger,
  );

  Future<void> _rename(
      BuildContext context, WidgetRef ref, Conversation conv) async {
    final ctrl = TextEditingController(text: conv.title);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Rename group',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 120,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Group name',
            counterText: '',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    final next = name?.trim() ?? '';
    if (next.isEmpty || next == conv.title) return;
    try {
      await ref.read(chatRepositoryProvider).renameGroup(conv.id, next);
      ref.read(conversationsProvider.notifier).refresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group renamed')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, Conversation conv) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Delete group?',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
        ),
        content: Text(
          '"${conv.title}" will be closed and hidden for every participant. '
          'Nobody will be able to open it or post in it again.',
          style: const TextStyle(color: AppColors.inkSoft, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: _destructive,
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(chatRepositoryProvider).deleteGroup(conv.id);
                if (context.mounted) {
                  Navigator.pop(context); // group info
                  Navigator.pop(context); // thread
                  ref.read(conversationsProvider.notifier).refresh();
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed: $e')),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _confirmLeave(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Leave group?',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
        ),
        content: const Text(
          'You will no longer receive messages from this group.',
          style: TextStyle(color: AppColors.inkSoft, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: _destructive,
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref
                    .read(chatRepositoryProvider)
                    .leaveGroup(conversation.id);
                if (context.mounted) {
                  Navigator.pop(context); // group info
                  Navigator.pop(context); // thread
                  ref.read(conversationsProvider.notifier).refresh();
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed: $e')),
                  );
                }
              }
            },
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Danger row (leave / delete)
// ─────────────────────────────────────────────────────────────────────────────

class _DangerRow extends StatelessWidget {
  const _DangerRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          child: Row(
            children: [
              ProIconWell(icon: icon, color: AppColors.danger),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.33,
                        fontWeight: FontWeight.w500,
                        color: AppColors.danger,
                      ),
                    ),
                    Text(subtitle, style: AppText.caption),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Member tile
// ─────────────────────────────────────────────────────────────────────────────

class _MemberTile extends ConsumerWidget {
  const _MemberTile({
    required this.member,
    required this.isAdmin,
    required this.myEmployeeId,
    required this.conversationId,
  });
  final ChatContact member;
  final bool isAdmin;
  final int? myEmployeeId;
  final int conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSelf = member.employeeId == myEmployeeId;
    return ProListRow(
      leading: ProAvatar(
        name: member.name,
        dark: isSelf,
        dot: member.online ? AppColors.live : null,
      ),
      title: member.name + (isSelf ? ' (You)' : ''),
      subtitle: (member.designation ?? '').isEmpty ? null : member.designation,
      pill: member.isAdmin
          ? ProPill(
              'Admin',
              color: AppColors.primary,
              background: Color.alphaBlend(
                  AppColors.primary.withOpacity(0.10), Colors.white),
            )
          : null,
      chevron: false,
      trailing: (isAdmin && !isSelf)
          ? PopupMenuButton<String>(
              tooltip: 'Member options',
              icon: const Icon(Icons.more_vert_rounded,
                  size: 20, color: AppColors.muted),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              onSelected: (action) => _onAction(action, context, ref),
              itemBuilder: (_) => [
                if (!member.isAdmin)
                  const PopupMenuItem(
                    value: 'promote',
                    child: Text('Make admin'),
                  ),
                if (member.isAdmin)
                  const PopupMenuItem(
                    value: 'demote',
                    child: Text('Remove admin'),
                  ),
                const PopupMenuItem(
                  value: 'remove',
                  child: Text('Remove from group',
                      style: TextStyle(color: AppColors.danger)),
                ),
              ],
            )
          : null,
    );
  }

  void _onAction(String action, BuildContext context, WidgetRef ref) async {
    try {
      final repo = ref.read(chatRepositoryProvider);
      switch (action) {
        case 'promote':
          await repo.makeAdmin(conversationId, member.employeeId);
          break;
        case 'demote':
          await repo.demoteAdmin(conversationId, member.employeeId);
          break;
        case 'remove':
          await repo.removeMember(conversationId, member.employeeId);
          break;
      }
      ref.read(conversationsProvider.notifier).refresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Done')),
        );
        Navigator.pop(context); // Refresh by re-entering.
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }
}
