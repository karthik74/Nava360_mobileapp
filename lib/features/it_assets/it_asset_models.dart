// Admin Tools — IT Assets models. Mirrors the backend's `ItAsset*` DTOs
// (`/api/admin-tools/it-assets/**`). Mobile is fill-only: BOE employees see
// their own assigned forms and submit answers here; building/editing the
// dynamic form and assigning it to staff stays web-only (Admin Tools).

import 'dart:convert';

DateTime? _dateTime(dynamic v) => (v is String && v.isNotEmpty) ? DateTime.tryParse(v) : null;

class ItAssetEntryStatus {
  ItAssetEntryStatus._();
  static const pending = 'PENDING';
  static const submitted = 'SUBMITTED';
}

/// One field definition from the admin-authored form schema
/// (`{"fields":[{key,label,type,required,options}]}`).
class ItAssetFieldDef {
  final String key;
  final String label;
  final String type; // text | number | date | dropdown | checkbox | textarea
  final bool required;
  final List<String> options;

  ItAssetFieldDef({
    required this.key,
    required this.label,
    required this.type,
    required this.required,
    required this.options,
  });

  factory ItAssetFieldDef.fromJson(Map<String, dynamic> json) {
    return ItAssetFieldDef(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      type: json['type'] as String? ?? 'text',
      required: json['required'] == true,
      options: ((json['options'] as List?) ?? const []).map((e) => e.toString()).toList(),
    );
  }
}

Map<String, String> _decodeAnswers(dynamic raw) {
  if (raw is String && raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
      }
    } catch (_) {
      // fall through to empty
    }
  }
  return const {};
}

List<ItAssetFieldDef> _decodeFields(dynamic raw) {
  if (raw is String && raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      final fields = decoded is Map ? decoded['fields'] : null;
      if (fields is List) {
        return fields.map((f) => ItAssetFieldDef.fromJson(f as Map<String, dynamic>)).toList();
      }
    } catch (_) {
      // fall through to empty
    }
  }
  return const [];
}

/// One assigned form + (once filled) its answers, for the signed-in employee.
class ItAssetFormEntry {
  final int id;
  final int templateId;
  final String templateName;
  final String period;
  final DateTime? dueDate;
  final String status;
  final Map<String, String> responseData;
  final List<ItAssetFieldDef> fields;
  final DateTime? submittedAt;
  final String? updatedBy;
  final DateTime? updatedAt;

  ItAssetFormEntry({
    required this.id,
    required this.templateId,
    required this.templateName,
    required this.period,
    required this.dueDate,
    required this.status,
    required this.responseData,
    required this.fields,
    required this.submittedAt,
    required this.updatedBy,
    required this.updatedAt,
  });

  bool get isSubmitted => status == ItAssetEntryStatus.submitted;

  factory ItAssetFormEntry.fromJson(Map<String, dynamic> json) {
    return ItAssetFormEntry(
      id: json['id'] as int,
      templateId: json['templateId'] as int,
      templateName: json['templateName'] as String? ?? '',
      period: json['period'] as String? ?? '',
      dueDate: _dateTime(json['dueDate']),
      status: json['status'] as String? ?? ItAssetEntryStatus.pending,
      responseData: _decodeAnswers(json['responseData']),
      fields: _decodeFields(json['templateFormSchema']),
      submittedAt: _dateTime(json['submittedAt']),
      updatedBy: json['updatedBy'] as String?,
      updatedAt: _dateTime(json['updatedAt']),
    );
  }
}
