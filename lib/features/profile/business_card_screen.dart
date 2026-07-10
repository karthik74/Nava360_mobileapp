import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/env.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import '../home/home_shell.dart' show employeeProfileProvider;

/// The hosted card page decodes `?data=` as base64(UTF-8 JSON) with exactly
/// these five keys (see Env.businessCardBaseUrl).
String buildBusinessCardUrl({
  required String name,
  required String designation,
  required String phone,
  required String email,
  required String location,
}) {
  final json = jsonEncode({
    'name': name,
    'designation': designation,
    'phone': phone,
    'email': email,
    'location': location,
  });
  final encoded = base64Encode(utf8.encode(json));
  return '${Env.businessCardBaseUrl}?data=${Uri.encodeComponent(encoded)}';
}

/// Digital business card: pre-fills the employee's details from their profile,
/// lets them adjust anything (the office address especially — branches don't
/// store one), and shares a link to the hosted card page which renders the
/// details from a `?data=<base64 JSON>` query parameter.
class BusinessCardScreen extends ConsumerStatefulWidget {
  const BusinessCardScreen({super.key});

  @override
  ConsumerState<BusinessCardScreen> createState() => _BusinessCardScreenState();
}

class _BusinessCardScreenState extends ConsumerState<BusinessCardScreen> {
  final _name = TextEditingController();
  final _designation = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _location = TextEditingController();
  bool _prefilled = false;

  @override
  void dispose() {
    for (final c in [_name, _designation, _phone, _email, _location]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Pre-fill once from the profile; after that the user's edits win.
  void _prefill(Map<String, dynamic>? profile, String displayName, String email) {
    if (_prefilled) return;
    _prefilled = true;
    String? f(String key) {
      final v = profile?[key]?.toString().trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    final fullName =
        [f('firstName'), f('lastName')].whereType<String>().join(' ').trim();
    _name.text = fullName.isNotEmpty ? fullName : displayName;
    _designation.text = f('designation') ?? '';
    _phone.text = f('phone') ?? '';
    _email.text = f('email') ?? email;
    _location.text = f('branchLabel') ?? '';
  }

  String _cardUrl() => buildBusinessCardUrl(
        name: _name.text.trim(),
        designation: _designation.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        location: _location.text.trim(),
      );

  bool get _valid => _name.text.trim().isNotEmpty;

  Future<void> _openCard() async {
    final ok = await launchUrl(Uri.parse(_cardUrl()),
        mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the card page.')));
    }
  }

  Future<void> _shareCard() async {
    final name = _name.text.trim();
    await Share.share(
      '$name — digital business card\n${_cardUrl()}',
      subject: '$name — business card',
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider);
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final empId = user.employeeId;
    final profileAsync =
        empId == null ? null : ref.watch(employeeProfileProvider(empId));
    final profile = profileAsync?.valueOrNull;
    final loading = profileAsync != null && profileAsync.isLoading && !_prefilled;
    if (!loading) _prefill(profile, user.displayName, user.email);

    final mq = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: AppColors.ink),
      ),
      body: GlassBackdrop(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  16,
                  mq.padding.top + kToolbarHeight + 8,
                  16,
                  mq.padding.bottom + 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppPageHeader(
                      title: 'My Business Card',
                      subtitle: 'Share your digital visiting card',
                    ),
                    const SizedBox(height: 16),
                    _CardPreview(
                      name: _name.text,
                      designation: _designation.text,
                      phone: _phone.text,
                      email: _email.text,
                      location: _location.text,
                    ),
                    const SizedBox(height: 18),
                    const AppSectionHeader(title: 'Card details'),
                    const SizedBox(height: 8),
                    _field('Full name', Icons.person_outline_rounded, _name),
                    _field('Designation', Icons.work_outline_rounded,
                        _designation),
                    _field('Phone', Icons.phone_outlined, _phone,
                        keyboard: TextInputType.phone),
                    _field('Email', Icons.email_outlined, _email,
                        keyboard: TextInputType.emailAddress),
                    _field('Office location', Icons.location_on_outlined,
                        _location,
                        lines: 3),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.open_in_new_rounded,
                                size: 17),
                            label: const Text('Preview card'),
                            onPressed: _valid ? _openCard : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.share_rounded, size: 17),
                            label: const Text('Share card'),
                            onPressed: _valid ? _shareCard : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'The link opens your card in any browser — nothing to '
                      'install for the person you share it with.',
                      style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _field(String label, IconData icon, TextEditingController controller,
      {TextInputType? keyboard, int lines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        minLines: lines,
        maxLines: lines,
        onChanged: (_) => setState(() {}), // live preview + button state
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 19),
        ),
      ),
    );
  }
}

/// Compact in-app preview approximating the hosted card design (teal panel
/// with a lime swoosh). The authoritative rendering is the shared web page.
class _CardPreview extends StatelessWidget {
  const _CardPreview({
    required this.name,
    required this.designation,
    required this.phone,
    required this.email,
    required this.location,
  });

  final String name;
  final String designation;
  final String phone;
  final String email;
  final String location;

  static const _teal = Color(0xFF0D7068);
  static const _lime = Color(0xFF8CC63F);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        color: _teal,
        child: Stack(
          children: [
            // Lime swoosh on the right, echoing the web design.
            Positioned(
              top: -30,
              right: -50,
              bottom: -30,
              child: Transform.rotate(
                angle: 0.35,
                child: Container(width: 110, color: _lime),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? 'Your name' : name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2),
                  ),
                  if (designation.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        designation,
                        style: const TextStyle(
                            color: _lime,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (phone.isNotEmpty)
                    _row(Icons.phone_rounded, phone),
                  if (email.isNotEmpty)
                    _row(Icons.email_rounded, email),
                  if (location.isNotEmpty)
                    _row(Icons.location_on_rounded, location),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 13, color: _lime),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                    color: Colors.white, fontSize: 11.5, height: 1.35),
              ),
            ),
          ],
        ),
      );
}
