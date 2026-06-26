/// Employee-facing view of one applicable, published policy. `read` reflects
/// acknowledgement of the CURRENT version, so a new version shows unread again.
class MyPolicy {
  final int id;
  final String title;
  final String? category;
  final String? description;
  final DateTime? effectiveDate;
  final String? versionNumber;
  final int? versionId;
  final DateTime? publishedAt;
  final bool allowDownload;
  final bool read;
  final DateTime? acknowledgedAt;

  MyPolicy({
    required this.id,
    required this.title,
    required this.read,
    required this.allowDownload,
    this.category,
    this.description,
    this.effectiveDate,
    this.versionNumber,
    this.versionId,
    this.publishedAt,
    this.acknowledgedAt,
  });

  factory MyPolicy.fromJson(Map<String, dynamic> j) => MyPolicy(
        id: (j['id'] as num).toInt(),
        title: j['title'] as String? ?? 'Policy',
        category: j['category'] as String?,
        description: j['description'] as String?,
        effectiveDate: _parseDate(j['effectiveDate']),
        versionNumber: j['versionNumber'] as String?,
        versionId: (j['versionId'] as num?)?.toInt(),
        publishedAt: _parseDate(j['publishedAt']),
        allowDownload: j['allowDownload'] as bool? ?? false,
        read: j['read'] as bool? ?? false,
        acknowledgedAt: _parseDate(j['acknowledgedAt']),
      );
}

DateTime? _parseDate(dynamic v) {
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}
