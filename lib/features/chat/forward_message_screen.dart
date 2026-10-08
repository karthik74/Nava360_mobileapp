import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'chat_controller.dart';
import 'chat_models.dart';
import 'chat_repository.dart';

/// Most chats one forward may fan out to (mirrors the server cap).
const _kMaxForwardTargets = 20;

/// WhatsApp-style "Forward to…" picker: tick any number of existing chats
/// and/or colleagues (their direct chat is found-or-created first), then
/// send. Pops with the number of chats the message reached.
class ForwardMessageScreen extends ConsumerStatefulWidget {
  const ForwardMessageScreen({super.key, required this.message});
  final ChatMessage message;

  @override
  ConsumerState<ForwardMessageScreen> createState() =>
      _ForwardMessageScreenState();
}

class _ForwardMessageScreenState extends ConsumerState<ForwardMessageScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _query = '';
  final Set<int> _convIds = {};
  final Set<int> _empIds = {};
  bool _sending = false;

  int get _total => _convIds.length + _empIds.length;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = v.trim());
    });
  }

  void _toggleConv(int id) {
    setState(() {
      if (_convIds.contains(id)) {
        _convIds.remove(id);
      } else if (_total < _kMaxForwardTargets) {
        _convIds.add(id);
      }
    });
  }

  void _toggleEmp(int id) {
    setState(() {
      if (_empIds.contains(id)) {
        _empIds.remove(id);
      } else if (_total < _kMaxForwardTargets) {
        _empIds.add(id);
      }
    });
  }

  Future<void> _send() async {
    if (_total == 0 || _sending) return;
    setState(() => _sending = true);
    try {
      final total = _total;
      final created = await ref.read(chatRepositoryProvider).forwardMessage(
            widget.message,
            conversationIds: _convIds.toList(),
            employeeIds: _empIds.toList(),
          );
      ref.read(conversationsProvider.notifier).refresh();
      if (!mounted) return;
      if (created.length < total) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Forwarded to ${created.length} of $total chats')),
        );
      }
      Navigator.pop(context, created.length);
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not forward: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final convs = ref.watch(conversationsProvider).valueOrNull ?? const [];
    final q = _query.toLowerCase();
    final chats = convs
        .where((c) => q.isEmpty || c.title.toLowerCase().contains(q))
        .toList();
    // Colleagues who already have a DM with us are reachable through that chat.
    final dmEmployeeIds = {
      for (final c in convs)
        if (c.isDirect && c.otherEmployeeId != null) c.otherEmployeeId!,
    };
    final contacts = q.length >= 2
        ? ref.watch(contactsSearchProvider(_query))
        : const AsyncValue<List<ChatContact>>.data([]);
    final myId = ref.watch(authUserProvider)?.employeeId;
    final msg = widget.message;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: proLightAppBar(
        context,
        title: 'Forward to…',
        subtitle: 'Pick the chats that should get this message',
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // ── The message being forwarded ────────────────────────────────
          GlassCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProIconWell(
                  icon: Icons.forward_rounded,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${msg.senderId == myId ? 'You' : msg.senderName}'
                        ' · ${DateFormat('h:mm a').format(msg.createdAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        msg.previewText,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ProSearchField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            autofocus: true,
            hint: 'Search chats or colleagues…',
            onClear: () => setState(() => _query = ''),
          ),
          if (chats.isNotEmpty) ...[
            const SizedBox(height: 16),
            const ProSectionHeader(
              title: 'Chats',
              small: true,
              trailing: Text(
                'Up to $_kMaxForwardTargets at once',
                style: AppText.caption,
              ),
            ),
            const SizedBox(height: 10),
            ProListGroup(
              dividerIndent: 66,
              children: [
                for (final c in chats)
                  _TargetTile(
                    title: c.title,
                    subtitle: c.isGroup
                        ? 'Group · ${c.members.length} members'
                        : (c.members
                                .where((m) =>
                                    m.employeeId == c.otherEmployeeId)
                                .firstOrNull
                                ?.designation ??
                            ''),
                    isGroup: c.isGroup,
                    imageUrl: c.otherAvatarUrl,
                    selected: _convIds.contains(c.id),
                    onTap: () => _toggleConv(c.id),
                  ),
              ],
            ),
          ],
          contacts.when(
            data: (list) {
              final people = list
                  .where((p) => !dmEmployeeIds.contains(p.employeeId))
                  .toList();
              if (people.isEmpty) {
                if (chats.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: ProEmpty(
                      icon: Icons.forward_to_inbox_rounded,
                      title: q.length < 2
                          ? 'No chats yet — type a name to find a colleague'
                          : 'Nothing matches "$_query"',
                    ),
                  );
                }
                return const SizedBox.shrink();
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  const ProSectionHeader(title: 'Colleagues', small: true),
                  const SizedBox(height: 10),
                  ProListGroup(
                    dividerIndent: 66,
                    children: [
                      for (final p in people)
                        _TargetTile(
                          title: p.name,
                          subtitle: p.designation ?? '',
                          imageUrl: p.avatarUrl,
                          selected: _empIds.contains(p.employeeId),
                          onTap: () => _toggleEmp(p.employeeId),
                        ),
                    ],
                  ),
                ],
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.only(top: 16),
              child: AppLoadingBlock(height: 60),
            ),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      // Send bar appears once something is ticked (was a floating button).
      bottomNavigationBar: _total == 0
          ? null
          : ProBottomBar(
              top: Text(
                '$_total of $_kMaxForwardTargets selected',
                style: AppText.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkSoft,
                ),
              ),
              children: [
                FilledButton.icon(
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded, size: 18),
                  label: Text('Forward ($_total)'),
                ),
              ],
            ),
    );
  }
}

class _TargetTile extends StatelessWidget {
  const _TargetTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.isGroup = false,
    this.imageUrl,
  });
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final bool isGroup;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    return ProListRow(
      onTap: onTap,
      chevron: false,
      leading: isGroup
          ? ProIconWell(
              icon: Icons.group_rounded,
              color: AppColors.primary,
              size: 42,
            )
          : SizedBox(
              width: 42,
              height: 42,
              child: Stack(
                children: [
                  ProAvatar(name: title),
                  if (url != null && url.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(42 * 0.31),
                      child: Image.network(
                        url,
                        width: 42,
                        height: 42,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        loadingBuilder: (_, child, progress) =>
                            progress == null ? child : const SizedBox.shrink(),
                      ),
                    ),
                ],
              ),
            ),
      title: title,
      subtitle: subtitle.isEmpty ? null : subtitle,
      trailing: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? AppColors.primary : AppColors.surface,
          border: Border.all(
            color: selected ? AppColors.primary : const Color(0xFFC6D3D6),
            width: 1.5,
          ),
        ),
        child: selected
            ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
            : null,
      ),
    );
  }
}
