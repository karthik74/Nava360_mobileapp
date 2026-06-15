import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'auth_repository.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Change password')),
      body: GlassBackdrop(
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppPageHeader(
                    title: 'Change password',
                    subtitle: 'Use at least 6 characters for your new password',
                  ),
                  const SizedBox(height: 18),
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _PasswordField(
                          controller: _current,
                          label: 'Current password',
                          obscure: _oCurrent,
                          onToggle: () =>
                              setState(() => _oCurrent = !_oCurrent),
                          textInputAction: TextInputAction.next,
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Enter your current password'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        _PasswordField(
                          controller: _next,
                          label: 'New password',
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
                        const SizedBox(height: 14),
                        _PasswordField(
                          controller: _confirm,
                          label: 'Confirm new password',
                          obscure: _oConfirm,
                          onToggle: () =>
                              setState(() => _oConfirm = !_oConfirm),
                          textInputAction: TextInputAction.done,
                          onSubmit: (_) => _submit(),
                          validator: (v) => (v != _next.text)
                              ? 'Passwords do not match'
                              : null,
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    AppErrorPanel(message: _error!),
                  ],
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 50,
                    child: FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                valueColor:
                                    AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : const Text('Update password'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.obscure,
    required this.onToggle,
    this.validator,
    this.textInputAction,
    this.onSubmit,
  });

  final TextEditingController controller;
  final String label;
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
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
        suffixIcon: IconButton(
          splashRadius: 18,
          icon: Icon(
            obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: AppColors.muted,
            size: 20,
          ),
          onPressed: onToggle,
        ),
      ),
    );
  }
}
