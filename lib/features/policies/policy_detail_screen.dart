import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/pro_ui.dart';
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
            return ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                ProEmpty(
                  icon: Icons.lock_outline_rounded,
                  title: 'Not available',
                  message: 'This policy is not available to you.',
                ),
              ],
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
    final p = widget.policy;
    final meta = [
      p.category ?? 'General',
      if (p.versionNumber != null) 'v${p.versionNumber}',
      if (p.effectiveDate != null) 'Effective ${df.format(p.effectiveDate!)}',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProHero(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
          children: [
            ProHeroIdentity(
              name: p.title,
              role: meta,
              icon: Icons.picture_as_pdf_rounded,
              tags: [
                _read
                    ? const ProHeroTag('Read', tone: ProTagTone.ok, icon: Icons.check_rounded)
                    : const ProHeroTag('Action needed', tone: ProTagTone.warn),
                if (p.publishedAt != null) ProHeroTag('Published ${df.format(p.publishedAt!)}'),
              ],
            ),
          ],
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadii.lg),
                border: Border.all(color: AppColors.hairline),
                boxShadow: AppShadows.card,
              ),
              padding: const EdgeInsets.all(6),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AppErrorPanel(message: _error!, onRetry: () {
                                setState(() {
                                  _loading = true;
                                  _error = null;
                                });
                                _load();
                              }),
                            ],
                          ),
                        )
                      : PDFView(
                          filePath: _pdfPath,
                          enableSwipe: true,
                          swipeHorizontal: false,
                          autoSpacing: true,
                          pageFling: true,
                        ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ProBottomBar(
          children: [
            if (_read)
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.successTint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.verified_rounded, color: AppColors.success, size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        widget.policy.acknowledgedAt != null
                            ? 'Acknowledged on ${df.format(widget.policy.acknowledgedAt!)}'
                            : 'Acknowledged',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              FilledButton.icon(
                onPressed: (_loading || _error != null || _acking) ? null : _acknowledge,
                icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: Text(
                  _acking ? 'Submitting…' : 'I have read and understood this policy',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
