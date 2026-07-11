import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'announcements_models.dart';

final announcementsRepositoryProvider =
    Provider((ref) => AnnouncementsRepository(ref.watch(apiClientProvider)));

class AnnouncementsRepository {
  AnnouncementsRepository(this._api);
  final ApiClient _api;

  /// Announcements addressed to the signed-in employee (pinned first).
  Future<List<MyAnnouncement>> getMyAnnouncements() {
    return _api.get<List<MyAnnouncement>>(
      '/api/announcements/my',
      parse: (d) {
        final list = (d is List) ? d : (d as Map<String, dynamic>?)?['content'] as List? ?? const [];
        return list
            .map((e) => MyAnnouncement.fromJson(e as Map<String, dynamic>))
            .toList();
      },
    );
  }

  Future<int> getUnreadCount() {
    return _api.get<int>(
      '/api/announcements/my/unread-count',
      parse: (d) => (d as num?)?.toInt() ?? 0,
    );
  }

  /// Reports that the employee TAPPED this announcement's push notification —
  /// powers the admin "who clicked" report. Fire-and-forget; never surfaces.
  Future<void> markOpened(int id) {
    return _api.post<void>('/api/announcements/$id/opened', parse: (_) {});
  }

  /// Marks read and returns the (now-read) announcement — used to open detail.
  Future<MyAnnouncement> markRead(int id) {
    return _api.post<MyAnnouncement>(
      '/api/announcements/$id/read',
      parse: (d) => MyAnnouncement.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<MyAnnouncement> acknowledge(int id) {
    return _api.post<MyAnnouncement>(
      '/api/announcements/$id/acknowledge',
      parse: (d) => MyAnnouncement.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<List<AnnouncementComment>> listComments(int id) {
    return _api.get<List<AnnouncementComment>>(
      '/api/announcements/$id/comments',
      parse: (d) => ((d as List?) ?? const [])
          .map((e) => AnnouncementComment.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<AnnouncementComment> addComment(int id, String comment) {
    return _api.post<AnnouncementComment>(
      '/api/announcements/$id/comment',
      body: {'comment': comment},
      parse: (d) => AnnouncementComment.fromJson(d as Map<String, dynamic>),
    );
  }
}
