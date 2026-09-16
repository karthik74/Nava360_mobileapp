/// A customer that tasks can be raised against.
/// Mirrors the backend `CustomerResponse`.
class Customer {
  Customer({
    required this.id,
    required this.customerName,
    this.customerCode,
    this.mobileNumber,
    this.email,
    this.address,
    this.branchId,
    this.branchName,
    this.assignedEmployeeId,
    this.assignedEmployeeName,
    this.status,
    this.createdBy,
    this.updatedBy,
    this.createdAt,
    this.updatedAt,
    this.customFields = const {},
    this.latitude,
    this.longitude,
    this.locationStatus,
  });

  final int id;
  final String customerName;
  final String? customerCode;
  final String? mobileNumber;
  final String? email;
  final String? address;
  final int? branchId;
  final String? branchName;
  final int? assignedEmployeeId;
  final String? assignedEmployeeName;
  final String? status;
  final String? createdBy;
  final String? updatedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Dynamic, admin-configured fields keyed by their field key (insertion order
  /// preserved). Values are returned as strings/numbers by the backend.
  final Map<String, dynamic> customFields;

  /// Stored pin, when the customer has one (0,0 is treated as none server-side).
  final double? latitude;
  final double? longitude;
  /// NOT_CAPTURED | CAPTURED | VERIFIED | NEEDS_CORRECTION | REJECTED
  final String? locationStatus;

  bool get hasLocation =>
      latitude != null &&
      longitude != null &&
      !(latitude!.abs() < 0.0001 && longitude!.abs() < 0.0001) &&
      locationStatus != 'REJECTED';

  bool get isActive => (status ?? 'ACTIVE').toUpperCase() == 'ACTIVE';

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: (j['id'] as num).toInt(),
        customerName: j['customerName'] as String? ?? 'Unnamed customer',
        customerCode: j['customerCode'] as String?,
        mobileNumber: j['mobileNumber'] as String?,
        email: j['email'] as String?,
        address: j['address'] as String?,
        branchId: (j['branchId'] as num?)?.toInt(),
        branchName: j['branchName'] as String?,
        assignedEmployeeId: (j['assignedEmployeeId'] as num?)?.toInt(),
        assignedEmployeeName: j['assignedEmployeeName'] as String?,
        status: j['status'] as String?,
        createdBy: j['createdBy'] as String?,
        updatedBy: j['updatedBy'] as String?,
        createdAt: j['createdAt'] is String
            ? DateTime.tryParse(j['createdAt'] as String)
            : null,
        updatedAt: j['updatedAt'] is String
            ? DateTime.tryParse(j['updatedAt'] as String)
            : null,
        customFields: (j['customFields'] as Map?)?.cast<String, dynamic>() ??
            const {},
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        locationStatus: j['locationStatus'] as String?,
      );
}
