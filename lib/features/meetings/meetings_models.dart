class MeetingRecord {
  final int id;
  final String title;
  final String? description;
  final String startTime;
  final String endTime;
  final String? location;
  final String? meetLink;
  final String? googleEventLink;
  final String status;
  final int attendeeCount;
  final String? createdBy;
  final bool host;

  MeetingRecord({
    required this.id,
    required this.title,
    required this.description,
    required this.startTime,
    required this.endTime,
    required this.location,
    required this.meetLink,
    required this.googleEventLink,
    required this.status,
    required this.attendeeCount,
    required this.createdBy,
    required this.host,
  });

  factory MeetingRecord.fromJson(Map<String, dynamic> j) => MeetingRecord(
        id: (j['id'] as num).toInt(),
        title: j['title'] as String? ?? '',
        description: j['description'] as String?,
        startTime: j['startTime'] as String,
        endTime: j['endTime'] as String,
        location: j['location'] as String?,
        meetLink: j['meetLink'] as String?,
        googleEventLink: j['googleEventLink'] as String?,
        status: j['status'] as String? ?? '',
        attendeeCount: (j['attendeeCount'] as num? ?? 0).toInt(),
        createdBy: j['createdBy'] as String?,
        host: j['host'] as bool? ?? false,
      );
}
