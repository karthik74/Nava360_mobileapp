import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import 'assets_models.dart';
import 'assets_repository.dart';
import 'my_assets_screen.dart' show assetStatusColor, assetStatusLabel;

/// Scans an asset QR/barcode with the camera (or manual entry) and shows the
/// matched asset. Used standalone and during audits.
class AssetScanScreen extends ConsumerStatefulWidget {
  const AssetScanScreen({super.key, this.auditId});

  /// When set, a successful scan is recorded against this audit.
  final int? auditId;

  @override
  ConsumerState<AssetScanScreen> createState() => _AssetScanScreenState();
}

class _AssetScanScreenState extends ConsumerState<AssetScanScreen> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _handling = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onCode(String code) async {
    if (_handling) return;
    setState(() => _handling = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (widget.auditId != null) {
        await ref.read(assetsRepositoryProvider).auditScan(widget.auditId!, code: code);
        messenger.showSnackBar(SnackBar(content: Text('Verified: $code')));
        setState(() => _handling = false);
        return;
      }
      final res = await ref.read(assetsRepositoryProvider).scan(code);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        builder: (_) => _ScanResultSheet(code: code, result: res),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Lookup failed: $e')));
    } finally {
      if (mounted) setState(() => _handling = false);
    }
  }

  Future<void> _manualEntry() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter asset code'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: const InputDecoration(
            hintText: 'Asset tag or code',
            helperText: 'Printed under the QR on the asset sticker.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Look up')),
        ],
      ),
    );
    if (code != null && code.isNotEmpty) _onCode(code);
  }

  @override
  Widget build(BuildContext context) {
    final audit = widget.auditId != null;
    return Scaffold(
      backgroundColor: AppColors.deep,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleSpacing: 4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              audit ? 'Audit scan' : 'Scan asset',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.3),
            ),
            const Text('QR / barcode', style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ProHeroIconButton(
              icon: Icons.keyboard_rounded,
              tooltip: 'Enter code',
              onTap: _manualEntry,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              for (final b in capture.barcodes) {
                final v = b.rawValue;
                if (v != null && v.isNotEmpty) {
                  _onCode(v);
                  break;
                }
              }
            },
          ),
          // Dark scrim under the transparent app bar so the title stays legible.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: MediaQuery.of(context).padding.top + kToolbarHeight + 24,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.deep.withValues(alpha: 0.85),
                      AppColors.deep.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Center(
            child: SizedBox(
              width: 248,
              height: 248,
              child: CustomPaint(painter: _FramePainter()),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 9, 16, 9),
                      decoration: BoxDecoration(
                        color: AppColors.deep.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_handling)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          else
                            const ProPulseDot(color: AppColors.live, size: 7),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _handling ? 'Looking up…' : 'Point the camera at the asset QR / barcode',
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _manualEntry,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
                        ),
                        icon: const Icon(Icons.keyboard_rounded, size: 18),
                        label: const Text('Enter code'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Viewfinder corner brackets.
class _FramePainter extends CustomPainter {
  const _FramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    const len = 34.0;
    const r = 18.0;
    final p = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final w = size.width;
    final h = size.height;
    // top-left
    canvas.drawPath(
        Path()
          ..moveTo(0, len)
          ..lineTo(0, r)
          ..arcToPoint(const Offset(r, 0), radius: const Radius.circular(r))
          ..lineTo(len, 0),
        p);
    // top-right
    canvas.drawPath(
        Path()
          ..moveTo(w - len, 0)
          ..lineTo(w - r, 0)
          ..arcToPoint(Offset(w, r), radius: const Radius.circular(r))
          ..lineTo(w, len),
        p);
    // bottom-right
    canvas.drawPath(
        Path()
          ..moveTo(w, h - len)
          ..lineTo(w, h - r)
          ..arcToPoint(Offset(w - r, h), radius: const Radius.circular(r))
          ..lineTo(w - len, h),
        p);
    // bottom-left
    canvas.drawPath(
        Path()
          ..moveTo(len, h)
          ..lineTo(r, h)
          ..arcToPoint(Offset(0, h - r), radius: const Radius.circular(r))
          ..lineTo(0, h - len),
        p);
    // faint full outline
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(r)),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ScanResultSheet extends StatelessWidget {
  const _ScanResultSheet({required this.code, required this.result});
  final String code;
  final AssetScanResult result;

  @override
  Widget build(BuildContext context) {
    final a = result.asset;
    final found = result.found && a != null;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFC6D3D6),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  ProIconWell(
                    icon: found ? Icons.check_circle_rounded : Icons.search_off_rounded,
                    color: found ? AppColors.success : AppColors.warning,
                    size: 46,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (found)
                          const Text(
                            'Asset found',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.success,
                            ),
                          ),
                        Text(
                          found ? a.name : 'No asset found',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 19,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.35,
                            color: AppColors.ink,
                          ),
                        ),
                        if (!found)
                          Text('No asset matches "$code".', style: AppText.caption),
                      ],
                    ),
                  ),
                ],
              ),
              if (found) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.neutralTint,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      a.assetTag,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF43585D),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text(
                      'Status',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.muted),
                    ),
                    const Spacer(),
                    ProPill(assetStatusLabel(a.status), color: assetStatusColor(a.status)),
                  ],
                ),
                const SizedBox(height: 4),
                const Divider(height: 1, color: AppColors.hairlineSoft),
                ProKeyValue(rows: [
                  if (a.categoryName != null || a.category != null)
                    MapEntry('Category', a.categoryName ?? a.category!),
                  if (a.brand != null || a.model != null)
                    MapEntry('Brand / Model', '${a.brand ?? ''} ${a.model ?? ''}'.trim()),
                  if (a.serialNumber != null) MapEntry('Serial', a.serialNumber!),
                  if (a.currentEmployeeName != null) MapEntry('Held by', a.currentEmployeeName!),
                  if (a.assetCondition != null) MapEntry('Condition', a.assetCondition!),
                ]),
              ],
              const SizedBox(height: 16),
              FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
            ],
          ),
        ),
      ),
    );
  }
}
