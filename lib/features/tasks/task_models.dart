import 'dart:convert';

class Task {
  Task({
    required this.id,
    required this.title,
    required this.status,
    this.description,
    this.dueDate,
    this.assignedToId,
    this.assignedToName,
    this.assignedById,
    this.assignedByName,
    this.priority,
    this.startDate,
    this.completedAt,
    this.formSchema,
    this.formResponse,
  });

  final int id;
  final String title;
  final String status;
  final String? description;
  final DateTime? dueDate;
  final int? assignedToId;
  final String? assignedToName;
  final int? assignedById;
  final String? assignedByName;
  final String? priority;
  final DateTime? startDate;
  final DateTime? completedAt;
  /// JSON string describing the form fields the assignee must fill.
  final String? formSchema;
  /// JSON string with the submitted values (null if not submitted yet).
  final String? formResponse;

  // Back-compat aliases used by existing list UI.
  String? get assignedBy => assignedByName;
  String? get projectName => null;

  factory Task.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
      return null;
    }

    return Task(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String? ?? 'Untitled task',
      status: json['status'] as String? ?? 'UNKNOWN',
      description: json['description'] as String?,
      dueDate: parseDate(json['dueDate']),
      assignedToId: (json['assignedToId'] as num?)?.toInt(),
      assignedToName: json['assignedToName'] as String?,
      assignedById: (json['assignedById'] as num?)?.toInt(),
      assignedByName: json['assignedByName'] as String?,
      priority: json['priority'] as String?,
      startDate: parseDate(json['startDate']),
      completedAt: parseDate(json['completedAt']),
      formSchema: json['formSchema'] as String?,
      formResponse: json['formResponse'] as String?,
    );
  }
}

// ---------------- Form schema (mirrors web FormBuilder JSON) ----------------

/// Supported field types. Unknown types fall back to plain text.
enum FieldType {
  text, textarea, number, mobile, email, date, time, day,
  daterange, select, radio, checkbox, file, multiimage;

  static FieldType from(String s) {
    final v = s.trim().toLowerCase();
    for (final t in values) {
      if (t.name == v) return t;
    }
    return FieldType.text;
  }
}

class FieldCondition {
  final String field;
  final String operator;
  final String? value;
  FieldCondition({required this.field, required this.operator, this.value});

  factory FieldCondition.fromJson(Map<String, dynamic> j) => FieldCondition(
        field: j['field'] as String,
        operator: j['operator'] as String,
        value: j['value'] as String?,
      );
}

class FormFieldDef {
  final String id;
  final FieldType type;
  final String label;
  final String name;
  final bool required;
  final String? placeholder;
  final String? helpText;
  final List<String> options;
  final int? maxLength;
  final int? minLength;
  final num? min;
  final num? max;
  final List<FieldCondition> visibleWhen;
  final String visibleWhenLogic; // "all" | "any"
  /// True when the assigner pre-fills this field at task-creation time.
  /// The assignee sees the value but cannot edit it.
  final bool assigned;

  FormFieldDef({
    required this.id,
    required this.type,
    required this.label,
    required this.name,
    required this.required,
    this.placeholder,
    this.helpText,
    this.options = const [],
    this.maxLength,
    this.minLength,
    this.min,
    this.max,
    this.visibleWhen = const [],
    this.visibleWhenLogic = 'all',
    this.assigned = false,
  });

  factory FormFieldDef.fromJson(Map<String, dynamic> j) {
    final opts = (j['options'] as List?)?.cast<String>() ?? const <String>[];
    final conds = (j['visibleWhen'] as List?)
            ?.map((e) => FieldCondition.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const <FieldCondition>[];
    return FormFieldDef(
      id: j['id'] as String,
      type: FieldType.from(j['type'] as String),
      label: j['label'] as String? ?? '',
      name: j['name'] as String,
      required: j['required'] == true,
      placeholder: j['placeholder'] as String?,
      helpText: j['helpText'] as String?,
      options: opts,
      maxLength: (j['maxLength'] as num?)?.toInt(),
      minLength: (j['minLength'] as num?)?.toInt(),
      min: j['min'] as num?,
      max: j['max'] as num?,
      visibleWhen: conds,
      visibleWhenLogic: (j['visibleWhenLogic'] as String?) ?? 'all',
      assigned: j['assigned'] == true,
    );
  }
}

class FormSchema {
  final List<FormFieldDef> fields;
  FormSchema(this.fields);

  static FormSchema? parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw);
      if (j is Map<String, dynamic> && j['fields'] is List) {
        final list = (j['fields'] as List)
            .map((e) => FormFieldDef.fromJson(e as Map<String, dynamic>))
            .toList();
        return FormSchema(list);
      }
    } catch (_) {/* ignore */}
    return null;
  }
}

typedef FormValues = Map<String, dynamic>;

FormValues parseFormValues(String? raw) {
  if (raw == null || raw.isEmpty) return {};
  try {
    final j = jsonDecode(raw);
    if (j is Map<String, dynamic>) return j;
  } catch (_) {/* ignore */}
  return {};
}

bool isFieldVisible(FormFieldDef f, FormValues values) {
  if (f.visibleWhen.isEmpty) return true;
  final results = f.visibleWhen.map((c) => _match(c, values[c.field]));
  return f.visibleWhenLogic == 'any'
      ? results.any((r) => r)
      : results.every((r) => r);
}

bool _match(FieldCondition c, dynamic v) {
  final isEmpty = v == null || v == '' || (v is List && v.isEmpty);
  if (c.operator == 'is_empty') return isEmpty;
  if (c.operator == 'is_not_empty') return !isEmpty;
  final target = (c.value ?? '').trim();
  if (v is List) {
    final list = v.cast<String>();
    switch (c.operator) {
      case 'equals': return list.length == 1 && list.first == target;
      case 'not_equals': return !(list.length == 1 && list.first == target);
      case 'contains': return list.contains(target);
      case 'not_contains': return !list.contains(target);
    }
  }
  final s = v == null ? '' : v.toString();
  switch (c.operator) {
    case 'equals': return s == target;
    case 'not_equals': return s != target;
    case 'contains': return s.toLowerCase().contains(target.toLowerCase());
    case 'not_contains': return !s.toLowerCase().contains(target.toLowerCase());
  }
  return false;
}
