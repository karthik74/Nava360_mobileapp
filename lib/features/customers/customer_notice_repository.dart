import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

/// Customer-notice API: templates, preview, generate, history, delivery.
/// Mirrors backend /api/notice-templates + /api/notices.

class NoticeTemplateSummary {
  final int id;
  final String name;
  final String? category;
  final String? language;

  const NoticeTemplateSummary(
      {required this.id, required this.name, this.category, this.language});

  factory NoticeTemplateSummary.fromJson(Map<String, dynamic> j) =>
      NoticeTemplateSummary(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String? ?? '',
        category: j['category'] as String?,
        language: j['language'] as String?,
      );
}

class NoticePreviewResult {
  final String? subject;
  final String html;
  final String? text;
  final List<String> missingVariables;

  const NoticePreviewResult(
      {this.subject, required this.html, this.text, required this.missingVariables});

  factory NoticePreviewResult.fromJson(Map<String, dynamic> j) => NoticePreviewResult(
        subject: j['subject'] as String?,
        html: j['html'] as String? ?? '',
        text: j['text'] as String?,
        missingVariables: ((j['missingVariables'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
}

class GeneratedNoticeSummary {
  final int id;
  final String referenceNumber;
  final String templateName;
  final String status;
  final String? generatedAt;
  final List<NoticeDeliverySummary> deliveries;

  const GeneratedNoticeSummary({
    required this.id,
    required this.referenceNumber,
    required this.templateName,
    required this.status,
    this.generatedAt,
    required this.deliveries,
  });

  factory GeneratedNoticeSummary.fromJson(Map<String, dynamic> j) =>
      GeneratedNoticeSummary(
        id: (j['id'] as num).toInt(),
        referenceNumber: j['referenceNumber'] as String? ?? '',
        templateName: j['templateName'] as String? ?? '',
        status: j['status'] as String? ?? 'GENERATED',
        generatedAt: j['generatedAt'] as String?,
        deliveries: ((j['deliveries'] as List?) ?? const [])
            .map((e) => NoticeDeliverySummary.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class NoticeDeliverySummary {
  final int id;
  final String channel;
  final String recipient;
  final String status;
  final String? failureReason;

  const NoticeDeliverySummary({
    required this.id,
    required this.channel,
    required this.recipient,
    required this.status,
    this.failureReason,
  });

  factory NoticeDeliverySummary.fromJson(Map<String, dynamic> j) =>
      NoticeDeliverySummary(
        id: (j['id'] as num).toInt(),
        channel: j['channel'] as String? ?? '',
        recipient: j['recipient'] as String? ?? '',
        status: j['status'] as String? ?? '',
        failureReason: j['failureReason'] as String?,
      );
}

List<Map<String, dynamic>> _pageContent(dynamic d) {
  if (d is List) return d.cast<Map<String, dynamic>>();
  final content = (d as Map<String, dynamic>)['content'] as List<dynamic>? ?? const [];
  return content.cast<Map<String, dynamic>>();
}

class CustomerNoticeRepository {
  CustomerNoticeRepository(this._api);
  final ApiClient _api;

  Future<List<NoticeTemplateSummary>> activeTemplates() {
    return _api.get<List<NoticeTemplateSummary>>(
      '/api/notice-templates',
      query: {'status': 'ACTIVE', 'size': 100},
      parse: (d) => _pageContent(d).map(NoticeTemplateSummary.fromJson).toList(),
    );
  }

  Future<NoticePreviewResult> preview(int customerId, int templateId) {
    return _api.post<NoticePreviewResult>(
      '/api/notices/preview',
      body: {'customerId': customerId, 'templateId': templateId},
      parse: (d) => NoticePreviewResult.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<GeneratedNoticeSummary> generate(int customerId, int templateId) {
    return _api.post<GeneratedNoticeSummary>(
      '/api/notices/generate',
      body: {'customerId': customerId, 'templateId': templateId},
      parse: (d) => GeneratedNoticeSummary.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<List<GeneratedNoticeSummary>> historyForCustomer(int customerId) {
    return _api.get<List<GeneratedNoticeSummary>>(
      '/api/notices',
      query: {'customerId': customerId, 'size': 30},
      parse: (d) => _pageContent(d).map(GeneratedNoticeSummary.fromJson).toList(),
    );
  }

  Future<List<NoticeDeliverySummary>> send(
    int noticeId, {
    required bool whatsapp,
    required bool email,
    String? phoneOverride,
    String? emailOverride,
  }) {
    return _api.post<List<NoticeDeliverySummary>>(
      '/api/notices/$noticeId/send',
      body: {
        'channels': [if (whatsapp) 'WHATSAPP', if (email) 'EMAIL'],
        if (phoneOverride != null && phoneOverride.isNotEmpty)
          'phoneOverride': phoneOverride,
        if (emailOverride != null && emailOverride.isNotEmpty)
          'emailOverride': emailOverride,
      },
      parse: (d) => ((d as List?) ?? const [])
          .map((e) => NoticeDeliverySummary.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<Uint8List> pdfBytes(int noticeId) {
    return _api.getBytes('/api/notices/$noticeId/pdf');
  }
}

final customerNoticeRepositoryProvider = Provider<CustomerNoticeRepository>(
  (ref) => CustomerNoticeRepository(ref.watch(apiClientProvider)),
);
