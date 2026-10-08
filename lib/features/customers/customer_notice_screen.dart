import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../core/pro_ui.dart';
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
        builder: (ctx, setSheet) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
              20, 10, 20, MediaQuery.of(ctx).padding.bottom + 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFC6D3D6),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text('Send ${n.referenceNumber}',
                  style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                      color: AppColors.ink)),
              const SizedBox(height: 12),
              GlassCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    CheckboxListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                      secondary: const ProIconWell(
                          icon: Icons.chat_rounded, color: AppColors.success),
                      title: Text(
                          'WhatsApp (${widget.customer.mobileNumber ?? 'no number'})',
                          style: const TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w500)),
                      value: whatsapp,
                      onChanged: (widget.customer.mobileNumber ?? '').isEmpty
                          ? null
                          : (v) => setSheet(() => whatsapp = v ?? false),
                    ),
                    const Divider(height: 1, indent: 62),
                    CheckboxListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                      secondary: const ProIconWell(
                          icon: Icons.mail_outline_rounded, color: AppColors.info),
                      title: Text('Email (${widget.customer.email ?? 'no email'})',
                          style: const TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w500)),
                      value: email,
                      onChanged: (widget.customer.email ?? '').isEmpty
                          ? null
                          : (v) => setSheet(() => email = v ?? false),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
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
    final c = widget.customer;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: proLightAppBar(
        context,
        title: 'Customer notices',
        subtitle: 'Customers · ${c.customerName}',
      ),
      bottomNavigationBar: _loading
          ? null
          : ProBottomBar(
              children: [
                OutlinedButton.icon(
                  onPressed: _working ? null : _doPreview,
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Preview'),
                ),
                FilledButton.icon(
                  onPressed: _working ? null : _doGenerate,
                  icon: _working
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Icon(Icons.description_outlined, size: 18),
                  label: Text(_working ? 'Working…' : 'Generate'),
                ),
              ],
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  // ── Customer ──
                  GlassCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        ProAvatar(name: c.customerName, size: 44),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.customerName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.title),
                              if ((c.customerCode ?? '').isNotEmpty)
                                Text(c.customerCode!, style: AppText.caption),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${_history.length}',
                                style: AppText.number.copyWith(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.ink)),
                            const Text('past notices', style: AppText.caption),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Generate ──
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const ProSectionHeader(title: 'Generate a notice'),
                        const SizedBox(height: 12),
                        ProField(
                          label: 'Template',
                          required: true,
                          child: DropdownButtonFormField<int>(
                            value: _templateId,
                            isExpanded: true,
                            hint: const Text('Choose a template'),
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
                        ),
                        const SizedBox(height: 12),
                        const ProNote(
                          'Preview the notice, then generate it from the bar below.',
                          tone: ProNoteTone.info,
                        ),
                        if (_preview != null) ...[
                          if (_preview!.missingVariables.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            ProNote(
                              'Missing: ${_preview!.missingVariables.map((v) => '{{$v}}').join(', ')}',
                              tone: ProNoteTone.warn,
                            ),
                          ],
                          const SizedBox(height: 12),
                          const Text('Preview', style: AppText.label),
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(top: 6),
                            padding: const EdgeInsets.all(12),
                            constraints: const BoxConstraints(maxHeight: 260),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceAlt,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.hairlineSoft),
                            ),
                            child: SingleChildScrollView(
                              child: Text(
                                (_preview!.text ?? '').isNotEmpty
                                    ? _preview!.text!
                                    : _stripHtml(_preview!.html),
                                style: const TextStyle(
                                    fontSize: 13, height: 1.5, color: AppColors.inkSoft),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),

                  // ── History ──
                  ProSectionHeader(
                      title: 'Past notices · ${_history.length}', small: true),
                  const SizedBox(height: 8),
                  if (_history.isEmpty)
                    const ProEmpty(
                      icon: Icons.description_outlined,
                      title: 'No notices yet',
                      message: 'No notices generated for this customer yet.',
                    ),
                  for (final n in _history) _historyCard(n),
                ],
              ),
            ),
    );
  }

  Widget _historyCard(GeneratedNoticeSummary n) {
    final cancelled = n.status == 'CANCELLED';
    final generated =
        n.generatedAt == null ? null : DateTime.tryParse(n.generatedAt!);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProIconWell(
                  icon: Icons.description_outlined,
                  color: cancelled ? AppColors.muted : AppColors.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(n.referenceNumber,
                          style: AppText.number.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: AppColors.ink)),
                      Text(
                        generated == null
                            ? n.templateName
                            : '${n.templateName} · ${DateFormat('d MMM y').format(generated)}',
                        style: AppText.caption,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                cancelled
                    ? ProPill.neutral(_sentence(n.status))
                    : ProPill.info(_sentence(n.status)),
              ],
            ),
            if (n.deliveries.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10, left: 46),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final d in n.deliveries.take(3))
                      d.status == 'FAILED'
                          ? ProPill.bad('${_sentence(d.channel)}: ${_sentence(d.status)}')
                          : ProPill.ok('${_sentence(d.channel)}: ${_sentence(d.status)}'),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.share_rounded, size: 16),
                    label: const Text('Share PDF'),
                    onPressed: _working ? null : () => _sharePdf(n),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text('Send'),
                    onPressed: _working || cancelled ? null : () => _sendSheet(n),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _sentence(String raw) {
    final s = raw.replaceAll('_', ' ').trim().toLowerCase();
    if (s.isEmpty) return raw;
    return s[0].toUpperCase() + s.substring(1);
  }

  static String _stripHtml(String html) => html
      .replaceAll(RegExp(r'<br\s*/?>'), '\n')
      .replaceAll('</p>', '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .trim();
}
