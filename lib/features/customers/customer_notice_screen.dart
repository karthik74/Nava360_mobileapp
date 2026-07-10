import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'customer_models.dart';
import 'customer_notice_repository.dart';

/// Generate + share customer notices from a customer's profile:
/// pick template → preview → generate → share/send PDF; past notices below.
class CustomerNoticeScreen extends ConsumerStatefulWidget {
  const CustomerNoticeScreen({super.key, required this.customer});
  final Customer customer;

  @override
  ConsumerState<CustomerNoticeScreen> createState() => _CustomerNoticeScreenState();
}

class _CustomerNoticeScreenState extends ConsumerState<CustomerNoticeScreen> {
  List<NoticeTemplateSummary> _templates = const [];
  List<GeneratedNoticeSummary> _history = const [];
  int? _templateId;
  NoticePreviewResult? _preview;
  bool _loading = true;
  bool _working = false;

  CustomerNoticeRepository get _repo => ref.read(customerNoticeRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _repo.activeTemplates(),
        _repo.historyForCustomer(widget.customer.id),
      ]);
      if (!mounted) return;
      setState(() {
        _templates = results[0] as List<NoticeTemplateSummary>;
        _history = results[1] as List<GeneratedNoticeSummary>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Could not load notices: $e');
    }
  }

  Future<void> _doPreview() async {
    final templateId = _templateId;
    if (templateId == null) return _snack('Pick a template first');
    setState(() => _working = true);
    try {
      final p = await _repo.preview(widget.customer.id, templateId);
      if (mounted) setState(() => _preview = p);
    } catch (e) {
      _snack('Preview failed: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _doGenerate() async {
    final templateId = _templateId;
    if (templateId == null) return _snack('Pick a template first');
    setState(() => _working = true);
    try {
      final n = await _repo.generate(widget.customer.id, templateId);
      _snack('Notice ${n.referenceNumber} generated');
      setState(() => _preview = null);
      await _load();
    } catch (e) {
      _snack('Generation failed: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _sharePdf(GeneratedNoticeSummary n) async {
    setState(() => _working = true);
    try {
      final bytes = await _repo.pdfBytes(n.id);
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}${Platform.pathSeparator}${n.referenceNumber}.pdf');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        text: 'Notice ${n.referenceNumber} — ${widget.customer.customerName}',
      );
    } catch (e) {
      _snack('Could not share PDF: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _sendSheet(GeneratedNoticeSummary n) async {
    var whatsapp = (widget.customer.mobileNumber ?? '').isNotEmpty;
    var email = (widget.customer.email ?? '').isNotEmpty;
    final sent = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 18, 20, MediaQuery.of(ctx).padding.bottom + 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Send ${n.referenceNumber}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                    'WhatsApp (${widget.customer.mobileNumber ?? 'no number'})',
                    style: const TextStyle(fontSize: 13.5)),
                value: whatsapp,
                onChanged: (widget.customer.mobileNumber ?? '').isEmpty
                    ? null
                    : (v) => setSheet(() => whatsapp = v ?? false),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Email (${widget.customer.email ?? 'no email'})',
                    style: const TextStyle(fontSize: 13.5)),
                value: email,
                onChanged: (widget.customer.email ?? '').isEmpty
                    ? null
                    : (v) => setSheet(() => email = v ?? false),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.send_rounded, size: 17),
                  label: const Text('Send notice'),
                  onPressed: (!whatsapp && !email)
                      ? null
                      : () => Navigator.pop(ctx, true),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (sent != true) return;
    setState(() => _working = true);
    try {
      final results =
          await _repo.send(n.id, whatsapp: whatsapp, email: email);
      final failed = results.where((r) => r.status == 'FAILED').length;
      _snack(failed == 0
          ? 'Notice sent'
          : '${results.length - failed} sent, $failed failed');
      await _load();
    } catch (e) {
      _snack('Send failed: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Customer Notices'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        elevation: 0.5,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(widget.customer.customerName,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink)),
                  Text(widget.customer.customerCode ?? '',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.muted)),
                  const SizedBox(height: 14),

                  // ── Generate ──
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Generate a notice',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int>(
                          value: _templateId,
                          isExpanded: true,
                          decoration:
                              const InputDecoration(labelText: 'Template'),
                          items: [
                            for (final t in _templates)
                              DropdownMenuItem(
                                value: t.id,
                                child: Text(
                                    '${t.name}${t.language != null ? ' (${t.language})' : ''}',
                                    overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (v) => setState(() {
                            _templateId = v;
                            _preview = null;
                          }),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _working ? null : _doPreview,
                                child: const Text('Preview'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                onPressed: _working ? null : _doGenerate,
                                child: Text(
                                    _working ? 'Working…' : 'Generate'),
                              ),
                            ),
                          ],
                        ),
                        if (_preview != null) ...[
                          const SizedBox(height: 10),
                          if (_preview!.missingVariables.isNotEmpty)
                            Text(
                              'Missing: ${_preview!.missingVariables.map((v) => '{{$v}}').join(', ')}',
                              style: const TextStyle(
                                  fontSize: 11.5, color: AppColors.warning),
                            ),
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(top: 6),
                            padding: const EdgeInsets.all(10),
                            constraints:
                                const BoxConstraints(maxHeight: 260),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceAlt,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: SingleChildScrollView(
                              child: Text(
                                (_preview!.text ?? '').isNotEmpty
                                    ? _preview!.text!
                                    : _stripHtml(_preview!.html),
                                style: const TextStyle(
                                    fontSize: 12, height: 1.45),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // ── History ──
                  const Text('Past notices',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  if (_history.isEmpty)
                    const AppEmptyState(
                      icon: Icons.description_outlined,
                      message: 'No notices generated for this customer yet.',
                    ),
                  for (final n in _history) _historyCard(n),
                ],
              ),
            ),
    );
  }

  Widget _historyCard(GeneratedNoticeSummary n) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(n.referenceNumber,
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: n.status == 'CANCELLED'
                      ? AppColors.muted.withValues(alpha: 0.12)
                      : AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(n.status,
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          Text(n.templateName,
              style:
                  const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
          if (n.deliveries.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 6,
                children: [
                  for (final d in n.deliveries.take(3))
                    Text('${d.channel}: ${d.status}',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: d.status == 'FAILED'
                              ? AppColors.danger
                              : AppColors.success,
                        )),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.share_rounded, size: 15),
                  label: const Text('Share PDF',
                      style: TextStyle(fontSize: 12)),
                  onPressed: _working ? null : () => _sharePdf(n),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.send_rounded, size: 15),
                  label:
                      const Text('Send', style: TextStyle(fontSize: 12)),
                  onPressed: _working || n.status == 'CANCELLED'
                      ? null
                      : () => _sendSheet(n),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _stripHtml(String html) => html
      .replaceAll(RegExp(r'<br\s*/?>'), '\n')
      .replaceAll('</p>', '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .trim();
}
