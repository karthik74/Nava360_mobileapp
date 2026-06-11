/// A reusable task form template (mirrors the backend `TaskFormTemplateResponse`).
/// Used by the customer-first flow to let a field employee pick which task to
/// perform for a customer.
class TaskTemplate {
  TaskTemplate({
    required this.id,
    required this.name,
    required this.taskType,
    required this.active,
    this.description,
    this.formSchema,
    this.defaultPriority,
    this.categoryId,
    this.categoryName,
    this.color,
    this.instructions,
    this.estimatedHours,
    this.defaultRequiresReview = true,
    this.defaultAllowAttachments = true,
  });

  final int id;
  final String name;
  final String taskType; // INTERNAL | CUSTOMER
  final bool active;
  final String? description;
  final String? formSchema;
  final String? defaultPriority;
  final int? categoryId;
  final String? categoryName;
  final String? color;
  final String? instructions;
  final double? estimatedHours;
  final bool defaultRequiresReview;
  final bool defaultAllowAttachments;

  bool get isCustomer => taskType.toUpperCase() == 'CUSTOMER';

  factory TaskTemplate.fromJson(Map<String, dynamic> j) => TaskTemplate(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String? ?? 'Untitled template',
        taskType: j['taskType'] as String? ?? 'INTERNAL',
        active: j['active'] != false,
        description: j['description'] as String?,
        formSchema: j['formSchema'] as String?,
        defaultPriority: j['defaultPriority'] as String?,
        categoryId: (j['categoryId'] as num?)?.toInt(),
        categoryName: j['categoryName'] as String?,
        color: j['color'] as String?,
        instructions: j['instructions'] as String?,
        estimatedHours: (j['estimatedHours'] as num?)?.toDouble(),
        defaultRequiresReview: j['defaultRequiresReview'] != false,
        defaultAllowAttachments: j['defaultAllowAttachments'] != false,
      );
}
