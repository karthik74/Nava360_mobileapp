import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/pro_ui.dart';
import '../../core/text_formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'chat_controller.dart';
import 'chat_models.dart';
import 'chat_repository.dart';
import 'chat_thread_screen.dart';

class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _nameCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  String _query = '';
  Timer? _debounce;
  final List<ChatContact> _selected = [];
  bool _creating = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
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

  void _toggleMember(ChatContact contact) {
    setState(() {
      final idx =
          _selected.indexWhere((c) => c.employeeId == contact.employeeId);
      if (idx >= 0) {
        _selected.removeAt(idx);
      } else {
        _selected.add(contact);
      }
    });
  }

  bool _isSelected(ChatContact contact) =>
      _selected.any((c) => c.employeeId == contact.employeeId);

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a group name')),
      );
      return;
    }
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one member')),
      );
      return;
    }
    setState(() => _creating = true);
    try {
      final conv = await ref.read(chatRepositoryProvider).createGroup(
            name,
            _selected.map((c) => c.employeeId).toList(),
          );
      if (!mounted) return;
      // Pop back to chat list, then open the new group.
      Navigator.pop(context); // create group screen
      Navigator.pop(context); // new chat screen (if stacked)
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatThreadScreen(conversation: conv),
        ),
      );
      ref.read(conversationsProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create group: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(groupCandidatesProvider(_query));
    final n = _selected.length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: proLightAppBar(
        context,
        title: 'Create group',
        subtitle: 'Name the group, then add colleagues',
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // ── Group details ──────────────────────────────────────────────
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ProSectionHeader(title: 'Group details'),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ProIconWell(
                      icon: Icons.group_rounded,
                      color: AppColors.primary,
                      size: 48,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ProField(
                        label: 'Group name',
                        required: true,
                        child: TextField(
                          controller: _nameCtrl,
                          textCapitalization: TextCapitalization.words,
                          inputFormatters: const [TitleCaseTextFormatter()],
                          cursorColor: AppColors.primary,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: AppColors.ink,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Type a group name',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // ── Members picked so far ──────────────────────────────────────
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ProSectionHeader(
                  title: 'Members',
                  trailing: n == 0
                      ? ProPill.neutral('None yet')
                      : ProPill.info('$n selected'),
                ),
                const SizedBox(height: 12),
                if (_selected.isEmpty)
                  const ProNote(
                    'Tap colleagues below to add them. They show up here.',
                    tone: ProNoteTone.info,
                  )
                else
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: _selected.map((c) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _MemberChip(
                            name: c.name,
                            onRemove: () => _toggleMember(c),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // ── Search members ─────────────────────────────────────────────
          _MemberSearchField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
          ),
          const SizedBox(height: 14),
          // ── Contact list with ticks ────────────────────────────────────
          contacts.when(
            data: (list) {
              if (list.isEmpty) {
                return ProEmpty(
                  icon: Icons.person_search_rounded,
                  title: _query.isEmpty
                      ? 'Search to find colleagues'
                      : 'No colleagues found',
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ProSectionHeader(
                    title: 'Colleagues · ${list.length}',
                    small: true,
                  ),
                  const SizedBox(height: 10),
                  ProListGroup(
                    dividerIndent: 66,
                    children: [
                      for (final c in list)
                        ProListRow(
                          leading: ProAvatar(
                            name: c.name,
                            dot: c.online ? AppColors.live : null,
                          ),
                          title: c.name,
                          subtitle: (c.designation ?? '').isEmpty
                              ? null
                              : c.designation,
                          chevron: false,
                          onTap: () => _toggleMember(c),
                          trailing: _Tick(selected: _isSelected(c)),
                        ),
                    ],
                  ),
                ],
              );
            },
            loading: () => const AppLoadingBlock(height: 80),
            error: (err, _) => AppErrorPanel(
              message: err.toString(),
              onRetry: () => ref.invalidate(groupCandidatesProvider(_query)),
            ),
          ),
        ],
      ),
      bottomNavigationBar: ProBottomBar(
        children: [
          FilledButton.icon(
            onPressed: _creating ? null : _create,
            icon: _creating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded, size: 20),
            label: Text(
              _creating
                  ? 'Creating…'
                  : (n == 0 ? 'Create group' : 'Create group · $n'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pieces
// ─────────────────────────────────────────────────────────────────────────────

/// Search field (ProSearchField look, keeps the title-case formatter).
class _MemberSearchField extends StatelessWidget {
  const _MemberSearchField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: const BorderSide(color: Color(0xFFDBE3E5)),
    );
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      textCapitalization: TextCapitalization.words,
      inputFormatters: const [TitleCaseTextFormatter()],
      style: const TextStyle(fontSize: 15, color: AppColors.ink),
      decoration: InputDecoration(
        hintText: 'Add members…',
        filled: true,
        fillColor: AppColors.surface,
        prefixIcon: const Icon(Icons.search_rounded, size: 21),
        contentPadding: const EdgeInsets.symmetric(vertical: 15),
        border: border,
        enabledBorder: border,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: AppColors.primary, width: 1.6),
        ),
      ),
    );
  }
}

/// Removable chip for a picked member.
class _MemberChip extends StatelessWidget {
  const _MemberChip({required this.name, required this.onRemove});
  final String name;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Color.alphaBlend(
          AppColors.primary.withOpacity(0.08), AppColors.surface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(color: AppColors.primary.withOpacity(0.25)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onRemove,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ProAvatar(name: name, size: 28),
              const SizedBox(width: 8),
              Text(
                name.split(' ').first,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.close_rounded, size: 15, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Round selection tick.
class _Tick extends StatelessWidget {
  const _Tick({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
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
    );
  }
}
