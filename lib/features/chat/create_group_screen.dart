import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final contacts = ref.watch(contactsSearchProvider(_query));
    final mq = MediaQuery.of(context);

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
                    padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_rounded, size: 20),
                          onPressed: () => Navigator.pop(context),
                          color: AppColors.inkSoft,
                        ),
                        const Expanded(
                          child: Text(
                            'Create Group',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        _creating
                            ? SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primary,
                                ),
                              )
                            : IconButton(
                                icon: const Icon(Icons.check_rounded, size: 22),
                                onPressed: _create,
                                color: AppColors.primary,
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
            // Group name
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: GlassCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shadow: AppShadows.soft,
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: AppColors.heroGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.group_rounded,
                          color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _nameCtrl,
                        textCapitalization: TextCapitalization.words,
                        inputFormatters: const [TitleCaseTextFormatter()],
                        cursorColor: AppColors.primary,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                        decoration: const InputDecoration(
                          isCollapsed: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                          border: InputBorder.none,
                          hintText: 'Group name',
                          hintStyle: TextStyle(
                            color: AppColors.muted,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Selected members chips
            if (_selected.isNotEmpty)
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: _selected.map((c) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InputChip(
                        avatar: UserAvatar(name: c.name, size: 24, radius: 12),
                        label: Text(
                          c.name.split(' ').first,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        deleteIcon: const Icon(Icons.close_rounded, size: 14),
                        onDeleted: () => _toggleMember(c),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                          side: BorderSide(
                              color: AppColors.primary.withOpacity(0.3)),
                        ),
                        backgroundColor: AppColors.primary.withOpacity(0.08),
                        deleteIconColor: AppColors.primary,
                      ),
                    );
                  }).toList(),
                ),
              ),
            // Search members
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
                            textCapitalization: TextCapitalization.words,
                            inputFormatters: const [TitleCaseTextFormatter()],
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
                              hintText: 'Add members…',
                              hintStyle: TextStyle(
                                color: AppColors.muted,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            // Contact list with checkboxes
            Expanded(
              child: contacts.when(
                data: (list) {
                  if (list.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(20),
                      child: AppEmptyState(
                        icon: Icons.person_search_rounded,
                        message: _query.isEmpty
                            ? 'Search to find colleagues'
                            : 'No colleagues found',
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final c = list[i];
                      final selected = _isSelected(c);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: GlassCard(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          shadow: const [],
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                UserAvatar(
                                    name: c.name, size: 40, radius: 20),
                                if (c.online)
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: AppColors.success,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: Colors.white, width: 2),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            title: Text(
                              c.name,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                            subtitle: Text(
                              c.designation ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.muted,
                              ),
                            ),
                            trailing: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: selected
                                    ? AppColors.heroGradient
                                    : null,
                                color: selected
                                    ? null
                                    : Colors.white.withOpacity(0.5),
                                border: Border.all(
                                  color: selected
                                      ? AppColors.primary
                                      : AppColors.muted.withOpacity(0.4),
                                  width: 1.5,
                                ),
                              ),
                              child: selected
                                  ? const Icon(Icons.check_rounded,
                                      size: 14, color: Colors.white)
                                  : null,
                            ),
                            onTap: () => _toggleMember(c),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadii.lg),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: AppLoadingBlock(height: 80),
                  ),
                ),
                error: (err, _) => Padding(
                  padding: const EdgeInsets.all(20),
                  child: AppErrorPanel(
                    message: err.toString(),
                    onRetry: () =>
                        ref.invalidate(contactsSearchProvider(_query)),
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
