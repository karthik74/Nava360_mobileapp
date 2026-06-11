/// Result of the public update check (`GET /api/public/app-version`).
class AppVersionCheck {
  AppVersionCheck({
    required this.platform,
    required this.latestVersionName,
    required this.latestVersionCode,
    required this.updateAvailable,
    required this.forceUpdate,
    this.downloadUrl,
    this.releaseNotes,
  });

  final String platform;
  final String latestVersionName;
  final int latestVersionCode;
  final String? downloadUrl;
  final String? releaseNotes;

  /// The caller's build is older than the latest published version.
  final bool updateAvailable;

  /// The caller must update before continuing.
  final bool forceUpdate;

  factory AppVersionCheck.fromJson(Map<String, dynamic> j) => AppVersionCheck(
        platform: j['platform'] as String? ?? 'ANDROID',
        latestVersionName: j['latestVersionName'] as String? ?? '',
        latestVersionCode: (j['latestVersionCode'] as num?)?.toInt() ?? 0,
        downloadUrl: j['downloadUrl'] as String?,
        releaseNotes: j['releaseNotes'] as String?,
        updateAvailable: j['updateAvailable'] == true,
        forceUpdate: j['forceUpdate'] == true,
      );
}
