import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'policies_models.dart';
import 'policies_repository.dart';
import 'policies_screen.dart';

/// Loads the employee's applicable policy by id (from their My Policies list).
final _myPolicyProvider =
    FutureProvider.autoDispose.family<MyPolicy?, int>((ref, id) async {
  final list = await ref.watch(policiesRepositoryProvider).myPolicies();
  for (final p in list) {
    if (p.id == id) return p;
  }
  return null;
});

class PolicyDetailScreen extends ConsumerWidget {
  const PolicyDetailScreen({super.key, required this.policyId});
  final int policyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_myPolicyProvider(policyId));
    return Scaffold(
      appBar: AppBar(title: const Text('Policy')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: AppErrorPanel(
            message: e.toString(),
            onRetry: () => ref.invalidate(_myPolicyProvider(policyId)),
          ),
        ),
        data: (policy) {
          if (policy == null || policy.versionId == null) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: AppEmptyState(
                icon: Icons.lock_outline_rounded,
                message: 'This policy is not available to you.',
              ),
            );
          }
          return _PolicyViewer(policy: policy);
        },
      ),
    );
  }
}

class _PolicyViewer extends ConsumerStatefulWidget {
  const _PolicyViewer({required this.policy});
  final MyPolicy policy;

  @override
  ConsumerState<_PolicyViewer> createState() => _PolicyViewerState();
}

class _PolicyViewerState extends ConsumerState<_PolicyViewer> {
  String? _pdfPath;
  String? _error;
  bool _loading = true;
  bool _acking = false;
  late bool _read = widget.policy.read;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final Uint8List bytes = await ref
          .read(policiesRepositoryProvider)
          .fetchPdf(widget.policy.id, widget.policy.versionId!);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/policy_${widget.policy.id}_v${widget.policy.versionId}.pdf');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      setState(() {
        _pdfPath = file.path;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _acknowledge() async {
    setState(() => _acking = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(policiesRepositoryProvider)
          .acknowledge(widget.policy.id, widget.policy.versionId!);
      ref.invalidate(myPoliciesProvider);
      ref.invalidate(_myPolicyProvider(widget.policy.id));
      if (!mounted) return;
      setState(() => _read = true);
      messenger.showSnackBar(const SnackBar(content: Text('Acknowledged ✓')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _acking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy');
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.policy.title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink),
              ),
              const SizedBox(height: 2),
              Text(
                [
                  widget.policy.category ?? 'General',
                  if (widget.policy.versionNumber != null) 'v${widget.policy.versionNumber}',
                  if (widget.policy.effectiveDate != null)
                    'Effective ${df.format(widget.policy.effectiveDate!)}',
                ].join(' · '),
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: AppErrorPanel(message: _error!, onRetry: () {
                        setState(() {
                          _loading = true;
                          _error = null;
                        });
                        _load();
                      }),
                    )
                  : PDFView(
                      filePath: _pdfPath,
                      enableSwipe: true,
                      swipeHorizontal: false,
                      autoSpacing: true,
                      pageFling: true,
                    ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _read
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.verified_rounded, color: AppColors.success, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        widget.policy.acknowledgedAt != null
                            ? 'Acknowledged on ${df.format(widget.policy.acknowledgedAt!)}'
                            : 'Acknowledged',
                        style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700),
                      ),
                    ],
                  )
                : SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: (_loading || _error != null || _acking) ? null : _acknowledge,
                      icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                      label: Text(_acking ? 'Submitting…' : 'I have read and understood this policy'),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
