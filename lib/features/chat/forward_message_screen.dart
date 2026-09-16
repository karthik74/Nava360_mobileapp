import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
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
    final mq = MediaQuery.of(context);
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

    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: PreferredSize(
          preferredSize:
              Size.fromHeight(mq.padding.top + AppChrome.appBarHeight),
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: GlassBlur.chrome,
                sigmaY: GlassBlur.chrome,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.62),
                  border: Border(
                    bottom: BorderSide(color: Colors.white.withOpacity(0.5)),
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_rounded, size: 20),
                          onPressed: () => Navigator.pop(context),
                          color: AppColors.inkSoft,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Forward to…',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.ink,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              Text(
                                widget.message.previewText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.md),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.50),
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      border: Border.all(color: Colors.white.withOpacity(0.6)),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        const Icon(Icons.search_rounded,
                            size: 18, color: AppColors.muted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            onChanged: _onSearchChanged,
                            autofocus: true,
                            cursorColor: AppColors.primary,
                            cursorWidth: 1.5,
                            style: const TextStyle(
                              fontSize: 13.5,
                              color: AppColors.ink,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: const InputDecoration(
                              isCollapsed: true,
                              contentPadding:
                                  EdgeInsets.symmetric(vertical: 13),
                              border: InputBorder.none,
                              hintText: 'Search chats or colleagues…',
                              hintStyle: TextStyle(
                                color: AppColors.muted,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        if (_searchCtrl.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.close_rounded,
                                size: 16, color: AppColors.muted),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          )
                        else
                          const SizedBox(width: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                    12, 6, 12, mq.padding.bottom + 90),
                children: [
                  if (chats.isNotEmpty) ...[
                    const AppSectionHeader(title: 'Chats'),
                    const SizedBox(height: 6),
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
                  contacts.when(
                    data: (list) {
                      final people = list
                          .where((p) => !dmEmployeeIds.contains(p.employeeId))
                          .toList();
                      if (people.isEmpty) {
                        if (chats.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.all(24),
                            child: AppEmptyState(
                              icon: Icons.forward_to_inbox_rounded,
                              message: q.length < 2
                                  ? 'No chats yet — type a name to find a colleague'
                                  : 'Nothing matches "$_query"',
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 10),
                          const AppSectionHeader(title: 'Colleagues'),
                          const SizedBox(height: 6),
                          for (final p in people)
                            _TargetTile(
                              title: p.name,
                              subtitle: p.designation ?? '',
                              imageUrl: p.avatarUrl,
                              selected: _empIds.contains(p.employeeId),
                              onTap: () => _toggleEmp(p.employeeId),
                            ),
                        ],
                      );
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.all(20),
                      child: AppLoadingBlock(height: 60),
                    ),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        floatingActionButton: _total == 0
            ? null
            : Padding(
                padding: EdgeInsets.only(bottom: mq.padding.bottom + 8),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: AppColors.heroGradient,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: AppShadows.lifted,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: _sending ? null : _send,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 11),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_sending)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            else
                              const Icon(Icons.send_rounded,
                                  color: Colors.white, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              'Forward ($_total)',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        shadow: const [],
        border: selected
            ? Border.all(color: AppColors.primary.withOpacity(0.5))
            : null,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          onTap: onTap,
          leading: isGroup
              ? Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: AppColors.heroGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.group_rounded,
                      color: Colors.white, size: 20),
                )
              : UserAvatar(
                  name: title, size: 40, radius: 20, imageUrl: imageUrl),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          subtitle: subtitle.isEmpty
              ? null
              : Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
          trailing: Icon(
            selected
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: selected ? AppColors.primary : AppColors.muted,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
        ),
      ),
    );
  }
}
