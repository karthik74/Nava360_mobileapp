import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'assets_models.dart';

final assetsRepositoryProvider =
    Provider((ref) => AssetsRepository(ref.watch(apiClientProvider)));

class AssetsRepository {
  AssetsRepository(this._api);
  final ApiClient _api;

  Future<List<AssetAssignment>> getMyAssets() {
    return _api.get<List<AssetAssignment>>(
      '/api/assets/my-assets',
      parse: (d) {
        final list = (d is List) ? d : const [];
        return list
            .map((e) => AssetAssignment.fromJson(e as Map<String, dynamic>))
            .toList();
      },
    );
  }

  Future<AssetScanResult> scan(String code) {
    return _api.get<AssetScanResult>(
      '/api/assets/scan',
      query: {'code': code},
      parse: (d) => AssetScanResult.fromJson(d as Map<String, dynamic>),
    );
  }

  Future<void> acknowledge(int assignmentId, bool accept, {String? remarks}) {
    return _api.post<void>(
      '/api/assets/assignments/$assignmentId/acknowledge',
      body: {'accept': accept, if (remarks != null) 'remarks': remarks},
      parse: (_) {},
    );
  }

  Future<void> returnRequest(int assetId,
      {required String returnedDate, String? conditionOnReturn}) {
    return _api.post<void>(
      '/api/assets/$assetId/return-request',
      body: {
        'returnedDate': returnedDate,
        if (conditionOnReturn != null) 'conditionOnReturn': conditionOnReturn,
      },
      parse: (_) {},
    );
  }

  Future<void> reportIncident(int assetId,
      {required String incidentType,
      required String incidentDate,
      String? description}) {
    return _api.post<void>(
      '/api/assets/$assetId/incident',
      body: {
        'incidentType': incidentType,
        'incidentDate': incidentDate,
        if (description != null) 'incidentDescription': description,
      },
      parse: (_) {},
    );
  }

  /// Records a physical-verification scan during an audit.
  Future<void> auditScan(int auditId,
      {required String code, String physicalStatus = 'FOUND', String? remarks}) {
    return _api.post<void>(
      '/api/assets/audits/$auditId/scan',
      body: {
        'code': code,
        'physicalStatus': physicalStatus,
        if (remarks != null) 'auditorRemarks': remarks,
      },
      parse: (_) {},
    );
  }
}
