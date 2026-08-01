// ─────────────────────────────────────────────────────────────────────────────
//  Models for Nearby Customers. Mirrors the backend NearbyCustomerResponse /
//  NearbyCustomersResponse / FieldVisitConfigResponse.
//
//  Fields the employee isn't permitted to see arrive as null from the server —
//  they are never sent and hidden here — so a null mobile number or outstanding
//  amount means "not authorised", and the UI simply omits the row.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:ui';

/// Collections classification. Drives the marker colour and the filter chips.
enum CustomerCategory {
  regular('REGULAR', 'Regular', Color(0xFF16A34A)), // green
  overdue('OVERDUE', 'Overdue', Color(0xFFEAB308)), // yellow
  npa('NPA', 'NPA', Color(0xFFDC2626)); // red

  const CustomerCategory(this.wire, this.label, this.color);

  final String wire;
  final String label;
  final Color color;

  static CustomerCategory parse(String? raw) {
    final v = (raw ?? '').toUpperCase();
    return CustomerCategory.values.firstWhere(
      (c) => c.wire == v,
      orElse: () => CustomerCategory.regular,
    );
  }
}

class NearbyCustomer {
  NearbyCustomer({
    required this.id,
    required this.customerName,
    required this.category,
    required this.distanceMeters,
    this.customerCode,
    this.mobileNumber,
    this.address,
    this.village,
    this.latitude,
    this.longitude,
    this.locationStatus,
    this.branchId,
    this.branchName,
    this.outstandingAmount,
    this.overdueDays,
    this.lastVisitedByMeAt,
    this.lastVisitedAt,
    this.visitedRecentlyByColleague = false,
    this.assignedToMe = false,
  });

  final int id;
  final String customerName;
  final String? customerCode;
  final String? mobileNumber;
  final String? address;
  final String? village;
  final double? latitude;
  final double? longitude;
  final CustomerCategory category;
  final String? locationStatus;
  final int? branchId;
  final String? branchName;
  final int distanceMeters;
  final double? outstandingAmount;
  final int? overdueDays;
  final DateTime? lastVisitedByMeAt;
  final DateTime? lastVisitedAt;
  final bool visitedRecentlyByColleague;
  final bool assignedToMe;

  bool get hasLocation => latitude != null && longitude != null;

  /// "450 m" / "2.4 km" — distance the way a person reads it.
  String get distanceLabel => distanceMeters < 1000
      ? '$distanceMeters m'
      : '${(distanceMeters / 1000).toStringAsFixed(distanceMeters < 10000 ? 1 : 0)} km';

  /// Where the customer is, in one line: village, branch or address.
  String get placeLabel {
    for (final s in [village, branchName, address]) {
      if (s != null && s.trim().isNotEmpty) return s.trim();
    }
    return '—';
  }

  factory NearbyCustomer.fromJson(Map<String, dynamic> j) => NearbyCustomer(
        id: (j['id'] as num).toInt(),
        customerName: j['customerName'] as String? ?? 'Unnamed customer',
        customerCode: j['customerCode'] as String?,
        mobileNumber: j['mobileNumber'] as String?,
        address: j['address'] as String?,
        village: j['village'] as String?,
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        category: CustomerCategory.parse(j['category'] as String?),
        locationStatus: j['locationStatus'] as String?,
        branchId: (j['branchId'] as num?)?.toInt(),
        branchName: j['branchName'] as String?,
        distanceMeters: (j['distanceMeters'] as num?)?.round() ?? 0,
        outstandingAmount: (j['outstandingAmount'] as num?)?.toDouble(),
        overdueDays: (j['overdueDays'] as num?)?.toInt(),
        lastVisitedByMeAt: _date(j['lastVisitedByMeAt']),
        lastVisitedAt: _date(j['lastVisitedAt']),
        visitedRecentlyByColleague: j['visitedRecentlyByColleague'] as bool? ?? false,
        assignedToMe: j['assignedToMe'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'customerName': customerName,
        'customerCode': customerCode,
        'mobileNumber': mobileNumber,
        'address': address,
        'village': village,
        'latitude': latitude,
        'longitude': longitude,
        'category': category.wire,
        'locationStatus': locationStatus,
        'branchId': branchId,
        'branchName': branchName,
        'distanceMeters': distanceMeters,
        'outstandingAmount': outstandingAmount,
        'overdueDays': overdueDays,
        'lastVisitedByMeAt': lastVisitedByMeAt?.toIso8601String(),
        'lastVisitedAt': lastVisitedAt?.toIso8601String(),
        'visitedRecentlyByColleague': visitedRecentlyByColleague,
        'assignedToMe': assignedToMe,
      };

  static DateTime? _date(dynamic v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;
}

/// A page of nearby customers plus the context needed to be honest about it.
class NearbyCustomersResult {
  NearbyCustomersResult({
    required this.customers,
    required this.radiusMeters,
    required this.generatedAt,
    required this.truncated,
    required this.maxResults,
    this.fromCache = false,
  });

  final List<NearbyCustomer> customers;
  final int radiusMeters;

  /// When the SERVER produced these rows — shown verbatim so a cached list can
  /// never be mistaken for a live one.
  final DateTime generatedAt;

  /// More customers matched than the server will return in one request.
  final bool truncated;
  final int maxResults;
  final bool fromCache;

  NearbyCustomersResult asCached() => NearbyCustomersResult(
        customers: customers,
        radiusMeters: radiusMeters,
        generatedAt: generatedAt,
        truncated: truncated,
        maxResults: maxResults,
        fromCache: true,
      );

  factory NearbyCustomersResult.fromJson(Map<String, dynamic> j) =>
      NearbyCustomersResult(
        customers: ((j['customers'] as List<dynamic>?) ?? const [])
            .map((e) => NearbyCustomer.fromJson(e as Map<String, dynamic>))
            .toList(),
        radiusMeters: (j['radiusMeters'] as num?)?.toInt() ?? 5000,
        generatedAt:
            DateTime.tryParse(j['generatedAt'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
        truncated: j['truncated'] as bool? ?? false,
        maxResults: (j['maxResults'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'customers': customers.map((c) => c.toJson()).toList(),
        'radiusMeters': radiusMeters,
        'generatedAt': generatedAt.toIso8601String(),
        'truncated': truncated,
        'maxResults': maxResults,
      };
}

/// Server-controlled tuning. Every value has a fallback here, so a failed fetch
/// degrades to sensible defaults instead of breaking tracking or the screen.
class FieldVisitConfig {
  const FieldVisitConfig({
    this.nearbyCustomersEnabled = true,
    this.visitDetectionEnabled = true,
    this.defaultRadiusMeters = 5000,
    this.maxRadiusMeters = 20000,
    this.radiusOptions = const [1000, 2000, 5000, 10000, 20000],
    this.maxResults = 300,
    this.cacheMinutes = 30,
    this.trackIntervalMovingSeconds = 60,
    this.trackIntervalStationarySeconds = 300,
    this.trackIntervalNearCustomerSeconds = 30,
    this.trackNearCustomerRadiusMeters = 200,
    this.trackMinDisplacementMeters = 25,
    this.visitEntryRadiusMeters = 50,
    this.visitMinDwellSeconds = 120,
  });

  final bool nearbyCustomersEnabled;
  final bool visitDetectionEnabled;
  final int defaultRadiusMeters;
  final int maxRadiusMeters;
  final List<int> radiusOptions;
  final int maxResults;
  final int cacheMinutes;
  final int trackIntervalMovingSeconds;
  final int trackIntervalStationarySeconds;
  final int trackIntervalNearCustomerSeconds;
  final int trackNearCustomerRadiusMeters;
  final int trackMinDisplacementMeters;
  final int visitEntryRadiusMeters;
  final int visitMinDwellSeconds;

  static const fallback = FieldVisitConfig();

  factory FieldVisitConfig.fromJson(Map<String, dynamic> j) => FieldVisitConfig(
        nearbyCustomersEnabled: j['nearbyCustomersEnabled'] as bool? ?? true,
        visitDetectionEnabled: j['visitDetectionEnabled'] as bool? ?? true,
        defaultRadiusMeters: (j['defaultRadiusMeters'] as num?)?.toInt() ?? 5000,
        maxRadiusMeters: (j['maxRadiusMeters'] as num?)?.toInt() ?? 20000,
        radiusOptions: ((j['radiusOptions'] as List<dynamic>?) ?? const [])
                .map((e) => (e as num).toInt())
                .toList()
                .let((l) => l.isEmpty ? const [1000, 2000, 5000, 10000, 20000] : l),
        maxResults: (j['maxResults'] as num?)?.toInt() ?? 300,
        cacheMinutes: (j['cacheMinutes'] as num?)?.toInt() ?? 30,
        trackIntervalMovingSeconds:
            (j['trackIntervalMovingSeconds'] as num?)?.toInt() ?? 60,
        trackIntervalStationarySeconds:
            (j['trackIntervalStationarySeconds'] as num?)?.toInt() ?? 300,
        trackIntervalNearCustomerSeconds:
            (j['trackIntervalNearCustomerSeconds'] as num?)?.toInt() ?? 30,
        trackNearCustomerRadiusMeters:
            (j['trackNearCustomerRadiusMeters'] as num?)?.toInt() ?? 200,
        trackMinDisplacementMeters:
            (j['trackMinDisplacementMeters'] as num?)?.toInt() ?? 25,
        visitEntryRadiusMeters:
            (j['visitEntryRadiusMeters'] as num?)?.toInt() ?? 50,
        visitMinDwellSeconds:
            (j['visitMinDwellSeconds'] as num?)?.toInt() ?? 120,
      );

  Map<String, dynamic> toJson() => {
        'nearbyCustomersEnabled': nearbyCustomersEnabled,
        'visitDetectionEnabled': visitDetectionEnabled,
        'defaultRadiusMeters': defaultRadiusMeters,
        'maxRadiusMeters': maxRadiusMeters,
        'radiusOptions': radiusOptions,
        'maxResults': maxResults,
        'cacheMinutes': cacheMinutes,
        'trackIntervalMovingSeconds': trackIntervalMovingSeconds,
        'trackIntervalStationarySeconds': trackIntervalStationarySeconds,
        'trackIntervalNearCustomerSeconds': trackIntervalNearCustomerSeconds,
        'trackNearCustomerRadiusMeters': trackNearCustomerRadiusMeters,
        'trackMinDisplacementMeters': trackMinDisplacementMeters,
        'visitEntryRadiusMeters': visitEntryRadiusMeters,
        'visitMinDwellSeconds': visitMinDwellSeconds,
      };
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
