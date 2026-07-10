import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/branding.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import '../home/home_shell.dart' show employeeProfileProvider;

/// vCard 3.0 for the QR code — scanning it saves the contact directly.
/// Mirrors the reference module's generator (github.com/Raghunandan1157/
/// digital-business-card script.js), but org/website come from branding
/// config instead of being hardcoded.
String buildVCard({
  required String name,
  required String designation,
  required String phone,
  required String email,
  required String location,
  required String organisation,
  required String website,
}) {
  final cleanPhone = phone.replaceAll(RegExp(r'[\s\-]'), '');
  final parts = name.trim().split(' ');
  final lastName = parts.length > 1 ? parts.last : '';
  final firstName =
      parts.length > 1 ? parts.sublist(0, parts.length - 1).join(' ') : name;
  return [
    'BEGIN:VCARD',
    'VERSION:3.0',
    'FN:$name',
    'N:$lastName;$firstName;;;',
    'TITLE:$designation',
    if (organisation.isNotEmpty) 'ORG:$organisation',
    'TEL;TYPE=CELL:$cleanPhone',
    'EMAIL:$email',
    if (website.isNotEmpty) 'URL:$website',
    'ADR;TYPE=WORK:;;${location.replaceAll('\n', ', ')};;;;',
    'END:VCARD',
  ].join('\n');
}

/// Digital business card: pre-fills the employee's details from their profile,
/// lets them adjust anything (the office address especially — branches don't
/// store one), renders the card natively in the reference design, and shares
/// it as a PNG IMAGE through the system share sheet (WhatsApp etc.). Fully
/// self-contained: no external card page involved.
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
  final _cardKey = GlobalKey();
  bool _prefilled = false;
  bool _sharing = false;

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

  bool get _valid => _name.text.trim().isNotEmpty;

  /// Rasterizes the card widget and hands the PNG to the system share sheet,
  /// so WhatsApp & co. receive an actual image file of the card.
  Future<void> _shareCard() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final boundary = _cardKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      // The card lays out at its design size (700×380); 2x makes a crisp
      // 1400×760 PNG without an oversized file.
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final safeName = _name.text
          .trim()
          .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
      final file = File(
          '${dir.path}${Platform.pathSeparator}business_card_$safeName.png');
      await file.writeAsBytes(bytes, flush: true);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: '${_name.text.trim()} — ${_designation.text.trim()}',
        subject: '${_name.text.trim()} — business card',
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not create the card image. Try again.')));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider);
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final branding = ref.watch(brandingProvider);
    final empId = user.employeeId;
    final profileAsync =
        empId == null ? null : ref.watch(employeeProfileProvider(empId));
    final profile = profileAsync?.valueOrNull;
    final loading = profileAsync != null && profileAsync.isLoading && !_prefilled;
    if (!loading) _prefill(profile, user.displayName, user.email);

    final vcard = buildVCard(
      name: _name.text.trim(),
      designation: _designation.text.trim(),
      phone: _phone.text.trim(),
      email: _email.text.trim(),
      location: _location.text.trim(),
      organisation: branding.companyName,
      website: branding.website,
    );

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
                    // The card renders at its design size inside a FittedBox;
                    // the RepaintBoundary is what gets rasterized on share.
                    FittedBox(
                      child: SizedBox(
                        width: BusinessCardView.designWidth,
                        height: BusinessCardView.designHeight,
                        child: RepaintBoundary(
                          key: _cardKey,
                          child: BusinessCardView(
                            name: _name.text.trim(),
                            designation: _designation.text.trim(),
                            phone: _phone.text.trim(),
                            email: _email.text.trim(),
                            location: _location.text.trim(),
                          ),
                        ),
                      ),
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
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        icon: _sharing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.share_rounded, size: 18),
                        label:
                            Text(_sharing ? 'Preparing…' : 'Share card image'),
                        onPressed: _valid && !_sharing ? _shareCard : null,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_valid) _QrSection(vcard: vcard),
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

/// The card, rendered natively to the reference module's exact design:
/// 700×380, teal panel with green/lime swooshes sweeping into a white logo
/// area (SVG paths transcribed from the repo's index.html), Playfair Display
/// name, lime contact bullets.
class BusinessCardView extends StatelessWidget {
  const BusinessCardView({
    super.key,
    required this.name,
    required this.designation,
    required this.phone,
    required this.email,
    required this.location,
  });

  static const double designWidth = 700;
  static const double designHeight = 380;

  static const Color teal = Color(0xFF0D7068);
  static const Color lime = Color(0xFF8CC63F);
  static const Color mint = Color(0xFFD0F0E0);

  final String name;
  final String designation;
  final String phone;
  final String email;
  final String location;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: CustomPaint(
        painter: const _CardBackgroundPainter(),
        child: Row(
          children: [
            // ── Left 55%: identity + contact rows on the teal panel ──
            Expanded(
              flex: 55,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(35, 32, 30, 25),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      decoration: const BoxDecoration(
                        border: Border(
                            left: BorderSide(color: lime, width: 3)),
                      ),
                      padding: const EdgeInsets.only(left: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name.isEmpty ? 'Your Name' : name,
                            style: const TextStyle(
                              fontFamily: 'PlayfairDisplay',
                              fontVariations: [ui.FontVariation('wght', 700)],
                              fontWeight: FontWeight.w700,
                              fontSize: 26,
                              color: lime,
                              letterSpacing: 0.5,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            designation.isEmpty ? 'Designation' : designation,
                            style: const TextStyle(
                              fontSize: 14,
                              color: mint,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _contactRow(Icons.phone, phone, 13),
                        const SizedBox(height: 12),
                        _contactRow(Icons.language, email, 13),
                        const SizedBox(height: 12),
                        _contactRow(Icons.location_on, location, 11.5,
                            color: const Color(0xFFE8E8E8), height: 1.55),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // ── Right 45%: logo on the white swoosh area ──
            Expanded(
              flex: 45,
              child: Center(
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: 200, maxHeight: 240),
                  child: Image.asset('assets/logo.png', fit: BoxFit.contain),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contactRow(IconData icon, String value, double fontSize,
      {Color color = const Color(0xFFF0F0F0), double height = 1.5}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.only(top: 2),
          decoration:
              const BoxDecoration(color: lime, shape: BoxShape.circle),
          child: Icon(icon, size: 13, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: fontSize,
              color: color,
              height: height,
              letterSpacing: 0.2,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// The background SVG from the reference design, transcribed path-for-path:
/// teal base, dark-green swoosh (70% opacity), lime swoosh, white logo area.
class _CardBackgroundPainter extends CustomPainter {
  const _CardBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Paths are authored in the 700×380 viewBox; scale to the actual size.
    canvas.scale(size.width / BusinessCardView.designWidth,
        size.height / BusinessCardView.designHeight);

    canvas.drawRect(const Rect.fromLTWH(0, 0, 700, 380),
        Paint()..color = BusinessCardView.teal);

    void swoosh(double x0, double c1x, double c1y, double c2x, double c2y,
        double x1, Color color) {
      final p = Path()
        ..moveTo(x0, 0)
        ..cubicTo(c1x, c1y, c2x, c2y, x1, 380)
        ..lineTo(700, 380)
        ..lineTo(700, 0)
        ..close();
      canvas.drawPath(p, Paint()..color = color);
    }

    swoosh(320, 360, 80, 300, 200, 340,
        const Color(0xFF5A9E1E).withValues(alpha: 0.7));
    swoosh(350, 400, 100, 330, 240, 380, BusinessCardView.lime);
    swoosh(390, 440, 110, 370, 260, 420, Colors.white);
  }

  @override
  bool shouldRepaint(covariant _CardBackgroundPainter oldDelegate) => false;
}

/// "Scan to save contact" — QR of the vCard, like the reference module's QR
/// section (which encodes a vCard so any camera app offers to add the person
/// to contacts).
class _QrSection extends StatelessWidget {
  const _QrSection({required this.vcard});

  final String vcard;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(Icons.qr_code_2_rounded,
                  size: 18, color: BusinessCardView.teal),
              SizedBox(width: 8),
              Text('Scan to save contact',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE8E8E8), width: 2),
            ),
            child: QrImageView(
              data: vcard,
              size: 180,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: BusinessCardView.teal),
              dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: BusinessCardView.teal),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Anyone can point their camera here to add you to their contacts.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
