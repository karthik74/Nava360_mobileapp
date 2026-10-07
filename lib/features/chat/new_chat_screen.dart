import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/env.dart';
import '../../core/pro_ui.dart';
import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'chat_controller.dart';
import 'chat_models.dart';
import 'chat_repository.dart';
import 'chat_thread_screen.dart';
import 'create_group_screen.dart';

class NewChatScreen extends ConsumerStatefulWidget {
  const NewChatScreen({super.key});

  @override
  ConsumerState<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends ConsumerState<NewChatScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  Future<void> _startDirectChat(ChatContact contact) async {
    // This screen is pushed onto the HomeShell's nested navigator (the chat
    // list lives inside a GoRouter ShellRoute), while showDialog defaults to
    // the ROOT navigator. Resolve both up front and pop each route from the
    // navigator that owns it — a bare Navigator.pop(context) here would pop
    // this screen (and then the chat list) instead of the loading dialog,
    // leaving the non-dismissible barrier on top: a black screen.
    final nav = Navigator.of(context);
    final rootNav = Navigator.of(context, rootNavigator: true);

    // Show a quick loading indicator. Track whether it is still up so a
    // system-back dismissal during the request can't make us pop something
    // else off the root navigator later.
    var loadingShown = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    ).whenComplete(() => loadingShown = false);

    void dismissLoading() {
      if (loadingShown) {
        loadingShown = false;
        rootNav.pop();
      }
    }

    try {
      final conv = await ref
          .read(chatRepositoryProvider)
          .getOrCreateDirect(contact.employeeId);
      dismissLoading();
      if (!mounted) return;
      // Refresh conversations list so it appears.
      ref.read(conversationsProvider.notifier).refresh();
      nav.pop(); // dismiss new-chat screen
      nav.push(
        MaterialPageRoute(
          builder: (_) => ChatThreadScreen(conversation: conv),
        ),
      );
    } catch (e) {
      dismissLoading();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open chat: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(contactsSearchProvider(_query));
    // Group creation is permission-gated (CHAT_GROUP_CREATE); DMs are open to all.
    final canCreateGroup =
        ref.watch(authUserProvider)?.hasPermission('CHAT_GROUP_CREATE') ??
            false;

    // Hero numbers from the colleague list the screen already loads.
    final loaded = contacts.valueOrNull;
    final online = loaded?.where((c) => c.online).length ?? 0;
    final working =
        loaded?.where((c) => c.status == WorkStatus.WORKING).length ?? 0;
    final onLeave =
        loaded?.where((c) => c.status == WorkStatus.ON_LEAVE).length ?? 0;

    return Scaffold(
      appBar: AppBar(),
      body: ProPage(
        hero: ProHero(
          title: 'New chat',
          subtitle: loaded == null
              ? 'Message a colleague or start a group'
              : '${loaded.length} colleague${loaded.length == 1 ? '' : 's'}'
                  ' · $online online',
          overlap: _SearchField(
            controller: _searchCtrl,
            hint: 'Search colleagues…',
            autofocus: true,
            onChanged: _onSearchChanged,
            onClear: () => setState(() => _query = ''),
          ),
          children: [
            if (loaded != null)
              ProHeroStats(
                stats: [
                  ProStat(
                    label: 'Online',
                    value: '$online',
                    sub: 'right now',
                    dot: AppColors.live,
                  ),
                  ProStat(
                    label: 'Working',
                    value: '$working',
                    sub: 'today',
                    dot: const Color(0xFF7FD3E3),
                  ),
                  ProStat(
                    label: 'On leave',
                    value: '$onLeave',
                    sub: 'today',
                    dot: const Color(0xFFF2B347),
                  ),
                ],
              ),
          ],
        ),
        children: [
          if (canCreateGroup)
            ProListGroup(
              children: [
                ProListRow(
                  leading: ProIconWell(
                    icon: Icons.group_add_rounded,
                    color: AppColors.primary,
                  ),
                  title: 'New group',
                  subtitle: 'Start a group chat with colleagues',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const CreateGroupScreen()),
                  ),
                ),
              ],
            ),
          // Contact list
          ...contacts.when(
            data: (list) {
              if (list.isEmpty) {
                return [
                  ProEmpty(
                    icon: Icons.person_search_rounded,
                    title: _query.isEmpty
                        ? 'Type a name to search colleagues'
                        : 'No colleagues match "$_query"',
                    message: 'Search by name, designation or department.',
                  ),
                ];
              }
              return [
                ProSectionHeader(
                  title: '${_query.isEmpty ? 'Colleagues' : 'Matches'}'
                      ' · ${list.length}',
                  small: true,
                ),
                ProListGroup(
                  dividerIndent: 66,
                  children: [
                    for (final c in list)
                      _ContactRow(
                        contact: c,
                        onTap: () => _startDirectChat(c),
                      ),
                  ],
                ),
              ];
            },
            loading: () => const [AppLoadingBlock(height: 80)],
            error: (err, _) => [
              AppErrorPanel(
                message: err.toString(),
                onRetry: () => ref.invalidate(contactsSearchProvider(_query)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Search field (ProSearchField look, keeps the title-case formatter)
// ─────────────────────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.hint,
    this.onClear,
    this.autofocus = false,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hint;
  final VoidCallback? onClear;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: const BorderSide(color: AppColors.hairline),
    );
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(15),
        boxShadow: AppShadows.lifted,
      ),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (_, v, __) => TextField(
          controller: controller,
          onChanged: onChanged,
          autofocus: autofocus,
          textInputAction: TextInputAction.search,
          textCapitalization: TextCapitalization.words,
          inputFormatters: const <TextInputFormatter>[TitleCaseTextFormatter()],
          style: const TextStyle(fontSize: 15, color: AppColors.ink),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: const Icon(Icons.search_rounded, size: 21),
            suffixIcon: v.text.isNotEmpty
                ? IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded, size: 19),
                    onPressed: () {
                      controller.clear();
                      onClear?.call();
                    },
                  )
                : null,
            contentPadding: const EdgeInsets.symmetric(vertical: 15),
            border: border,
            enabledBorder: border,
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(color: AppColors.primary, width: 1.6),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Contact row
// ─────────────────────────────────────────────────────────────────────────────

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.contact, required this.onTap});
  final ChatContact contact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sub = [
      if (contact.designation != null) contact.designation!,
      if (contact.department != null) contact.department!,
    ].join(' • ');
    return ProListRow(
      leading: _PhotoAvatar(
        name: contact.name,
        imageUrl: Env.fileUrl(contact.avatarUrl),
        online: contact.online,
      ),
      title: contact.name,
      subtitle: sub.isEmpty ? null : sub,
      pill: _statusPill(contact.status),
      onTap: onTap,
    );
  }

  static Widget? _statusPill(WorkStatus status) {
    if (status == WorkStatus.OFF) return null;
    return status == WorkStatus.WORKING
        ? ProPill.ok('Working')
        : ProPill.warn('On leave');
  }
}

/// [ProAvatar] squircle with the person's photo on top when there is one and
/// a lime online dot.
class _PhotoAvatar extends StatelessWidget {
  const _PhotoAvatar({
    required this.name,
    this.imageUrl,
    this.online = false,
  });
  final String name;
  final String? imageUrl;
  final bool online;

  static const double _size = 42;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ProAvatar(name: name, size: _size),
          if (url != null && url.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(_size * 0.31),
              child: Image.network(
                url,
                width: _size,
                height: _size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : const SizedBox.shrink(),
              ),
            ),
          if (online)
            Positioned(
              right: -3,
              bottom: -3,
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: AppColors.live,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
