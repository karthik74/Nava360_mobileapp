import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme.dart';
import 'assets_models.dart';
import 'assets_repository.dart';

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
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
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
        content: TextField(controller: ctrl, autofocus: true),
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.auditId != null ? 'Audit scan' : 'Scan asset'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.keyboard_rounded), tooltip: 'Enter code', onPressed: _manualEntry),
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
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white.withOpacity(0.8), width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            bottom: 28,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _handling ? 'Looking up…' : 'Point the camera at the asset QR / barcode',
                  style: const TextStyle(color: Colors.white, fontSize: 12.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanResultSheet extends StatelessWidget {
  const _ScanResultSheet({required this.code, required this.result});
  final String code;
  final AssetScanResult result;

  @override
  Widget build(BuildContext context) {
    final a = result.asset;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!result.found || a == null) ...[
            const Text('No asset found',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink)),
            const SizedBox(height: 8),
            Text('No asset matches "$code".', style: const TextStyle(color: AppColors.muted)),
          ] else ...[
            Text(a.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink)),
            const SizedBox(height: 4),
            Text(a.assetTag, style: const TextStyle(fontFamily: 'monospace', color: AppColors.muted)),
            const SizedBox(height: 12),
            _row('Status', a.status),
            if (a.categoryName != null || a.category != null) _row('Category', a.categoryName ?? a.category!),
            if (a.brand != null || a.model != null) _row('Brand / Model', '${a.brand ?? ''} ${a.model ?? ''}'.trim()),
            if (a.serialNumber != null) _row('Serial', a.serialNumber!),
            if (a.currentEmployeeName != null) _row('Held by', a.currentEmployeeName!),
            if (a.assetCondition != null) _row('Condition', a.assetCondition!),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
          ),
        ],
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 110, child: Text(k, style: const TextStyle(color: AppColors.muted, fontSize: 13))),
            Expanded(child: Text(v, style: const TextStyle(color: AppColors.ink, fontSize: 13, fontWeight: FontWeight.w600))),
          ],
        ),
      );
}
