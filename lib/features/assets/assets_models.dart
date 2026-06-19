// Employee-facing asset models (mirror of the backend asset DTOs).

DateTime? _date(dynamic v) {
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}

class AssetAssignment {
  final int id;
  final int assetId;
  final String assetName;
  final String assetTag;
  final String? serialNumber;
  final String? imeiNumber;
  final String assignedToType;
  final int? employeeId;
  final String? employeeName;
  final DateTime? assignedDate;
  final DateTime? expectedReturnDate;
  final DateTime? returnedDate;
  final bool acknowledgementRequired;
  final String acknowledgementStatus;
  final String? documentUrl;
  final String status;
  final String? notes;

  AssetAssignment({
    required this.id,
    required this.assetId,
    required this.assetName,
    required this.assetTag,
    required this.assignedToType,
    this.serialNumber,
    this.imeiNumber,
    required this.acknowledgementRequired,
    required this.acknowledgementStatus,
    required this.status,
    this.employeeId,
    this.employeeName,
    this.assignedDate,
    this.expectedReturnDate,
    this.returnedDate,
    this.documentUrl,
    this.notes,
  });

  factory AssetAssignment.fromJson(Map<String, dynamic> j) => AssetAssignment(
        id: (j['id'] as num).toInt(),
        assetId: (j['assetId'] as num).toInt(),
        assetName: j['assetName'] as String? ?? 'Asset',
        assetTag: j['assetTag'] as String? ?? '',
        serialNumber: j['serialNumber'] as String?,
        imeiNumber: j['imeiNumber'] as String?,
        assignedToType: j['assignedToType'] as String? ?? 'EMPLOYEE',
        employeeId: (j['employeeId'] as num?)?.toInt(),
        employeeName: j['employeeName'] as String?,
        assignedDate: _date(j['assignedDate']),
        expectedReturnDate: _date(j['expectedReturnDate']),
        returnedDate: _date(j['returnedDate']),
        acknowledgementRequired: j['acknowledgementRequired'] as bool? ?? false,
        acknowledgementStatus: j['acknowledgementStatus'] as String? ?? 'NOT_REQUIRED',
        documentUrl: j['documentUrl'] as String?,
        status: j['status'] as String? ?? 'ACTIVE',
        notes: j['notes'] as String?,
      );
}

class Asset {
  final int id;
  final String name;
  final String assetTag;
  final String? category;
  final String? categoryName;
  final String? brand;
  final String? model;
  final String? serialNumber;
  final String? imeiNumber;
  final String? qrCode;
  final String status;
  final String? assetCondition;
  final String? currentEmployeeName;
  final String? currentLocationType;
  final DateTime? warrantyEndDate;
  final String? notes;

  Asset({
    required this.id,
    required this.name,
    required this.assetTag,
    required this.status,
    this.category,
    this.categoryName,
    this.brand,
    this.model,
    this.serialNumber,
    this.imeiNumber,
    this.qrCode,
    this.assetCondition,
    this.currentEmployeeName,
    this.currentLocationType,
    this.warrantyEndDate,
    this.notes,
  });

  factory Asset.fromJson(Map<String, dynamic> j) => Asset(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String? ?? 'Asset',
        assetTag: j['assetTag'] as String? ?? '',
        category: j['category'] as String?,
        categoryName: j['categoryName'] as String?,
        brand: j['brand'] as String?,
        model: j['model'] as String?,
        serialNumber: j['serialNumber'] as String?,
        imeiNumber: j['imeiNumber'] as String?,
        qrCode: j['qrCode'] as String?,
        status: j['status'] as String? ?? 'AVAILABLE',
        assetCondition: j['assetCondition'] as String?,
        currentEmployeeName: j['currentEmployeeName'] as String?,
        currentLocationType: j['currentLocationType'] as String?,
        warrantyEndDate: _date(j['warrantyEndDate']),
        notes: j['notes'] as String?,
      );
}

class AssetScanResult {
  final bool found;
  final Asset? asset;
  AssetScanResult({required this.found, this.asset});

  factory AssetScanResult.fromJson(Map<String, dynamic> j) => AssetScanResult(
        found: j['found'] as bool? ?? false,
        asset: j['asset'] == null ? null : Asset.fromJson(j['asset'] as Map<String, dynamic>),
      );
}
