import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import 'auth_controller.dart';
import 'auth_repository.dart';
import 'login_screen.dart' show AuthPasswordRules, AuthVisibilityToggle;

/// Lets a signed-in user change their password (verifies the current one).
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _oCurrent = true;
  bool _oNext = true;
  bool _oConfirm = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      await ref.read(authRepositoryProvider).changePassword(
            currentPassword: _current.text,
            newPassword: _next.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Password changed successfully.')),
        );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: proLightAppBar(
        context,
        title: 'Change password',
        subtitle: 'Account · Security',
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics()),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  if (user != null) ...[
                    _AccountRow(
                      name: user.displayName,
                      meta: [user.username, _roleLabel(user.role)]
                          .where((e) => e.isNotEmpty)
                          .join(' · '),
                    ),
                    const SizedBox(height: 14),
                  ],
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const ProSectionHeader(title: 'Your password'),
                        const SizedBox(height: 12),
                        ProField(
                          label: 'Current password',
                          child: _PasswordField(
                            controller: _current,
                            hint: 'Enter your current password',
                            obscure: _oCurrent,
                            onToggle: () =>
                                setState(() => _oCurrent = !_oCurrent),
                            textInputAction: TextInputAction.next,
                            validator: (v) => (v == null || v.isEmpty)
                                ? 'Enter your current password'
                                : null,
                          ),
                        ),
                        const SizedBox(height: 14),
                        ProField(
                          label: 'New password',
                          helper:
                              'Use at least 6 characters for your new password.',
                          child: _PasswordField(
                            controller: _next,
                            hint: 'At least 6 characters',
                            obscure: _oNext,
                            onToggle: () => setState(() => _oNext = !_oNext),
                            textInputAction: TextInputAction.next,
                            validator: (v) {
                              if (v == null || v.length < 6) {
                                return 'At least 6 characters';
                              }
                              if (v == _current.text) {
                                return 'New password must differ from current';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 14),
                        ProField(
                          label: 'Confirm new password',
                          child: _PasswordField(
                            controller: _confirm,
                            hint: 'Re-enter new password',
                            obscure: _oConfirm,
                            onToggle: () =>
                                setState(() => _oConfirm = !_oConfirm),
                            textInputAction: TextInputAction.done,
                            onSubmit: (_) => _submit(),
                            validator: (v) => (v != _next.text)
                                ? 'Passwords do not match'
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _PasswordChecks(
                    current: _current,
                    next: _next,
                    confirm: _confirm,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    ProNote(_error!, tone: ProNoteTone.bad),
                  ],
                ],
              ),
            ),
            ProBottomBar(
              children: [
                FilledButton.icon(
                  onPressed: _loading ? null : _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    disabledBackgroundColor:
                        _loading ? AppColors.primary : null,
                    disabledForegroundColor: _loading ? Colors.white : null,
                  ),
                  icon: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Icon(Icons.lock_reset_rounded, size: 19),
                  label: const Text('Update password'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Turns a role code such as BRANCH_MANAGER into "Branch manager".
String _roleLabel(String role) {
  final s = role.replaceAll('_', ' ').trim().toLowerCase();
  if (s.isEmpty) return '';
  return s[0].toUpperCase() + s.substring(1);
}

/// Compact identity row: whose password is being changed.
class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.name, required this.meta});
  final String name;
  final String meta;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      child: Row(
        children: [
          ProAvatar(name: name, size: 42, dark: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.15,
                    color: AppColors.ink,
                  ),
                ),
                if (meta.isNotEmpty)
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const ProIconWell(
            icon: Icons.verified_user_outlined,
            color: AppColors.success,
          ),
        ],
      ),
    );
  }
}

/// Live checklist for the new password (mirrors the form validators; the
/// form still validates on submit exactly as before).
class _PasswordChecks extends StatelessWidget {
  const _PasswordChecks({
    required this.current,
    required this.next,
    required this.confirm,
  });

  final TextEditingController current;
  final TextEditingController next;
  final TextEditingController confirm;

  @override
  Widget build(BuildContext context) {
    final rules = <(String, bool Function())>[
      ('At least 6 characters', () => next.text.length >= 6),
      (
        'Different from your current password',
        () => next.text.isNotEmpty && next.text != current.text
      ),
      (
        'Both new passwords match',
        () => confirm.text.isNotEmpty && confirm.text == next.text
      ),
    ];
    final all = Listenable.merge([current, next, confirm]);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListenableBuilder(
            listenable: all,
            builder: (context, _) {
              final met = rules.where((r) => r.$2()).length;
              final label = '$met of ${rules.length}';
              return ProSectionHeader(
                title: 'Password checks',
                trailing: met == rules.length
                    ? ProPill.ok(label)
                    : ProPill.neutral(label),
              );
            },
          ),
          const SizedBox(height: 12),
          AuthPasswordRules(listenable: all, rules: rules),
        ],
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.hint,
    required this.obscure,
    required this.onToggle,
    this.validator,
    this.textInputAction,
    this.onSubmit,
  });

  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final VoidCallback onToggle;
  final FormFieldValidator<String>? validator;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmit;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmit,
      validator: validator,
      style: const TextStyle(
        fontSize: 15,
        color: AppColors.ink,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
        suffixIcon: AuthVisibilityToggle(obscure: obscure, onPressed: onToggle),
      ),
    );
  }
}
