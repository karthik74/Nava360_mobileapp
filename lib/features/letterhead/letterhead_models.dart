// Admin Tools — Letter Head model — mirrors the backend
// `AdminLetterheadResponse` DTO (see nava360-web `src/api/adminLetterhead.ts`
// and the Spring `AdminLetterheadController`/`AdminLetterheadTemplate`
// entity). Unlike the other three Admin Tools features this is not a CRUD
// register: the server only ever stores ONE guide file per user (a
// letterhead template image/PDF) — there is no persisted alignment/offset/
// scale. On the web the drag-to-align/export step (`LetterHeadPage.tsx`,
// via pdf-lib) is purely client-side and its output is only ever downloaded
// locally, never uploaded — so this mobile port intentionally limits itself
// to view / upload / delete of the guide file. See the mobile screen for the
// full rationale.

DateTime? _date(dynamic v) {
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}

/// The current user's saved letterhead guide file (`AdminLetterheadResponse`).
class AdminLetterhead {
  final int id;
  final String fileName;
  final String? contentType;
  final String url;
  final DateTime? uploadedAt;

  AdminLetterhead({
    required this.id,
    required this.fileName,
    required this.url,
    this.contentType,
    this.uploadedAt,
  });

  factory AdminLetterhead.fromJson(Map<String, dynamic> j) => AdminLetterhead(
        id: (j['id'] as num).toInt(),
        fileName: j['fileName'] as String? ?? 'letterhead',
        contentType: j['contentType'] as String?,
        url: j['url'] as String? ?? '',
        uploadedAt: _date(j['uploadedAt']),
      );

  bool get isImage {
    final ct = contentType?.toLowerCase() ?? '';
    if (ct.startsWith('image/')) return true;
    final n = fileName.toLowerCase();
    return n.endsWith('.jpg') || n.endsWith('.jpeg') || n.endsWith('.png') || n.endsWith('.webp');
  }

  bool get isPdf {
    final ct = contentType?.toLowerCase() ?? '';
    return ct == 'application/pdf' || fileName.toLowerCase().endsWith('.pdf');
  }
}
