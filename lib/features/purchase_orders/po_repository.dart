import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'po_models.dart';

final poRepositoryProvider =
    Provider((ref) => PoRepository(ref.watch(apiClientProvider)));

/// Pulls the `content` list out of a paged `ApiResponse<PageResponse<T>>`
/// `data` payload, tolerating a bare list for forward-compatibility.
List<Map<String, dynamic>> _pageContent(dynamic d) {
  if (d is List) return d.cast<Map<String, dynamic>>();
  final content = (d as Map<String, dynamic>)['content'] as List<dynamic>? ?? const [];
  return content.cast<Map<String, dynamic>>();
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Admin Tools · Purchase Orders API client — typed wrappers over
/// `/api/admin/purchase-orders/**`. All requests carry the JWT +
/// `X-Device-Type: MOBILE` via the shared [ApiClient] interceptor;
/// server-side RBAC (`ADMIN_PO_*`) gates every call.
class PoRepository {
  PoRepository(this._api);
  final ApiClient _api;

  static const _base = '/api/admin/purchase-orders';

  /// Paged list, optionally scoped to one creator (`createdByUserId`).
  Future<List<PurchaseOrder>> list({
    int? createdByUserId,
    int page = 0,
    int size = 100,
  }) {
    return _api.get<List<PurchaseOrder>>(
      _base,
      query: {
        if (createdByUserId != null) 'createdByUserId': createdByUserId,
        'page': page,
        'size': size,
      },
      parse: (d) => _pageContent(d).map(PurchaseOrder.fromJson).toList(),
    );
  }

  Future<PurchaseOrder> get(int id) {
    return _api.get<PurchaseOrder>(
      '$_base/$id',
      parse: (d) => PurchaseOrder.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<PurchaseOrder> create({
    required DateTime poDate,
    String? supplierName,
    String? supplierAddress,
    String? supplierGstin,
    String? shippingName,
    String? shippingAddress,
    String? remarks,
    required List<PoItem> items,
  }) {
    return _api.post<PurchaseOrder>(
      _base,
      body: _body(
        poDate: poDate,
        supplierName: supplierName,
        supplierAddress: supplierAddress,
        supplierGstin: supplierGstin,
        shippingName: shippingName,
        shippingAddress: shippingAddress,
        remarks: remarks,
        items: items,
      ),
      parse: (d) => PurchaseOrder.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<PurchaseOrder> update(
    int id, {
    required DateTime poDate,
    String? supplierName,
    String? supplierAddress,
    String? supplierGstin,
    String? shippingName,
    String? shippingAddress,
    String? remarks,
    required List<PoItem> items,
  }) {
    return _api.put<PurchaseOrder>(
      '$_base/$id',
      body: _body(
        poDate: poDate,
        supplierName: supplierName,
        supplierAddress: supplierAddress,
        supplierGstin: supplierGstin,
        shippingName: shippingName,
        shippingAddress: shippingAddress,
        remarks: remarks,
        items: items,
      ),
      parse: (d) => PurchaseOrder.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<void> delete(int id) {
    return _api.raw.delete('$_base/$id');
  }

  Future<PoDashboard> dashboard() {
    return _api.get<PoDashboard>(
      '$_base/report/dashboard',
      parse: (d) => PoDashboard.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<List<PoAuditLog>> auditTrail() {
    return _api.get<List<PoAuditLog>>(
      '$_base/audit',
      parse: (d) => ((d as List?) ?? const [])
          .map((e) => PoAuditLog.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  // ── Request-body builder ──────────────────────────────────────────────

  Map<String, dynamic> _body({
    required DateTime poDate,
    String? supplierName,
    String? supplierAddress,
    String? supplierGstin,
    String? shippingName,
    String? shippingAddress,
    String? remarks,
    required List<PoItem> items,
  }) =>
      {
        'poDate': _isoDate(poDate),
        'supplierName': supplierName,
        'supplierAddress': supplierAddress,
        'supplierGstin': supplierGstin,
        'shippingName': shippingName,
        'shippingAddress': shippingAddress,
        'remarks': remarks,
        'items': items.map((i) => i.toInputJson()).toList(),
      };
}
