// Admin Tools — Purchase Orders models — mirror of the backend
// `AdminPurchaseOrder*` DTOs (see nava360-web `src/types.ts` and
// `src/api/adminPurchaseOrders.ts`, and the Spring `PurchaseOrderController`).
// Ported near-verbatim from the standalone office "Purchase Order" app: a
// supplier + shipping header, item lines with a fixed GST-slab dropdown
// (0/5/18%), and subtotal/GST/grand-total rollups computed server-side.

DateTime? _date(dynamic v) {
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}

double? _num(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String && v.isNotEmpty) return double.tryParse(v);
  return null;
}

double _num0(dynamic v) => _num(v) ?? 0;

/// Fixed GST slabs offered on each item line — same as the original
/// standalone app and `PurchaseOrderDocument.tsx`'s `GST_OPTIONS`.
class PoConstants {
  PoConstants._();
  static const gstOptions = <int>[0, 5, 18];
}

/// One saved item line (`AdminPurchaseOrderItem`).
class PoItem {
  final int? id;
  final String description;
  final double quantity;
  final double unitPrice;
  final double gstPercent;
  final double lineTotal;

  PoItem({
    this.id,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.gstPercent,
    this.lineTotal = 0,
  });

  factory PoItem.fromJson(Map<String, dynamic> j) => PoItem(
        id: (j['id'] as num?)?.toInt(),
        description: j['description'] as String? ?? '',
        quantity: _num0(j['quantity']),
        unitPrice: _num0(j['unitPrice']),
        gstPercent: _num0(j['gstPercent']),
        lineTotal: _num0(j['lineTotal']),
      );

  /// `AdminPurchaseOrderItemInput` — create/update payload shape.
  Map<String, dynamic> toInputJson() => {
        'description': description,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'gstPercent': gstPercent,
      };

  /// Base (pre-GST) amount for this line: qty × unit price.
  double get baseAmount => quantity * unitPrice;

  /// GST amount for this line, computed client-side for the live running
  /// total while editing (the server recomputes canonically on save).
  double get gstAmount => baseAmount * (gstPercent / 100);

  double get total => baseAmount + gstAmount;

  PoItem copyWith({
    String? description,
    double? quantity,
    double? unitPrice,
    double? gstPercent,
  }) =>
      PoItem(
        id: id,
        description: description ?? this.description,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice ?? this.unitPrice,
        gstPercent: gstPercent ?? this.gstPercent,
        lineTotal: lineTotal,
      );
}

/// Full purchase order (`AdminPurchaseOrder`).
class PurchaseOrder {
  final int id;
  final String poNumber;
  final DateTime? poDate;
  final String? supplierName;
  final String? supplierAddress;
  final String? supplierGstin;
  final String? shippingName;
  final String? shippingAddress;
  final double subtotal;
  final double gstTotal;
  final double grandTotal;
  final String? remarks;
  final int? createdByUserId;
  final String? createdByUsername;
  final List<PoItem> items;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  PurchaseOrder({
    required this.id,
    required this.poNumber,
    required this.items,
    this.poDate,
    this.supplierName,
    this.supplierAddress,
    this.supplierGstin,
    this.shippingName,
    this.shippingAddress,
    this.subtotal = 0,
    this.gstTotal = 0,
    this.grandTotal = 0,
    this.remarks,
    this.createdByUserId,
    this.createdByUsername,
    this.createdAt,
    this.updatedAt,
  });

  factory PurchaseOrder.fromJson(Map<String, dynamic> j) => PurchaseOrder(
        id: (j['id'] as num).toInt(),
        poNumber: j['poNumber'] as String? ?? '',
        poDate: _date(j['poDate']),
        supplierName: j['supplierName'] as String?,
        supplierAddress: j['supplierAddress'] as String?,
        supplierGstin: j['supplierGstin'] as String?,
        shippingName: j['shippingName'] as String?,
        shippingAddress: j['shippingAddress'] as String?,
        subtotal: _num0(j['subtotal']),
        gstTotal: _num0(j['gstTotal']),
        grandTotal: _num0(j['grandTotal']),
        remarks: j['remarks'] as String?,
        createdByUserId: (j['createdByUserId'] as num?)?.toInt(),
        createdByUsername: j['createdByUsername'] as String?,
        items: ((j['items'] as List?) ?? const [])
            .map((e) => PoItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        createdAt: _date(j['createdAt']),
        updatedAt: _date(j['updatedAt']),
      );
}

/// Per-user rollup row of the dashboard (`AdminPurchaseOrderUserStat`).
class PoUserStat {
  final int? userId;
  final String username;
  final int orderCount;
  final double totalValue;

  PoUserStat({
    this.userId,
    required this.username,
    required this.orderCount,
    required this.totalValue,
  });

  factory PoUserStat.fromJson(Map<String, dynamic> j) => PoUserStat(
        userId: (j['userId'] as num?)?.toInt(),
        username: j['username'] as String? ?? '—',
        orderCount: (j['orderCount'] as num?)?.toInt() ?? 0,
        totalValue: _num0(j['totalValue']),
      );
}

/// `/api/admin/purchase-orders/report/dashboard` payload
/// (`AdminPurchaseOrderDashboard`).
class PoDashboard {
  final int totalOrders;
  final double totalValue;
  final int thisMonthOrders;
  final double thisMonthValue;
  final List<PoUserStat> byUser;

  PoDashboard({
    required this.totalOrders,
    required this.totalValue,
    required this.thisMonthOrders,
    required this.thisMonthValue,
    required this.byUser,
  });

  factory PoDashboard.fromJson(Map<String, dynamic> j) => PoDashboard(
        totalOrders: (j['totalOrders'] as num?)?.toInt() ?? 0,
        totalValue: _num0(j['totalValue']),
        thisMonthOrders: (j['thisMonthOrders'] as num?)?.toInt() ?? 0,
        thisMonthValue: _num0(j['thisMonthValue']),
        byUser: ((j['byUser'] as List?) ?? const [])
            .map((e) => PoUserStat.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// One row of `/api/admin/purchase-orders/audit` (`AdminPurchaseOrderAuditLog`).
class PoAuditLog {
  final int id;
  final String entityType;
  final int? entityId;
  final String action;
  final int? actorUserId;
  final String? actorName;
  final String? actorRole;
  final String? beforeJson;
  final String? afterJson;
  final String? metaJson;
  final DateTime? createdAt;

  PoAuditLog({
    required this.id,
    required this.entityType,
    required this.action,
    this.entityId,
    this.actorUserId,
    this.actorName,
    this.actorRole,
    this.beforeJson,
    this.afterJson,
    this.metaJson,
    this.createdAt,
  });

  factory PoAuditLog.fromJson(Map<String, dynamic> j) => PoAuditLog(
        id: (j['id'] as num).toInt(),
        entityType: j['entityType'] as String? ?? '',
        entityId: (j['entityId'] as num?)?.toInt(),
        action: j['action'] as String? ?? '',
        actorUserId: (j['actorUserId'] as num?)?.toInt(),
        actorName: j['actorName'] as String?,
        actorRole: j['actorRole'] as String?,
        beforeJson: j['beforeJson'] as String?,
        afterJson: j['afterJson'] as String?,
        metaJson: j['metaJson'] as String?,
        createdAt: _date(j['createdAt']),
      );
}
