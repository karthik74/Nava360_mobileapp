import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'payslips_models.dart';

final payslipsRepositoryProvider =
    Provider((ref) => PayslipsRepository(ref.watch(apiClientProvider)));

class PayslipsRepository {
  PayslipsRepository(this._api);
  final ApiClient _api;

  Future<List<PayrollRecord>> getMyPayrolls() {
    return _api.get<List<PayrollRecord>>(
      '/api/payrolls/my',
      parse: (d) {
        if (d is List) {
          return d
              .map((e) => PayrollRecord.fromJson(e as Map<String, dynamic>))
              .toList();
        }
        if (d is Map<String, dynamic>) {
          final content = d['content'] as List<dynamic>? ?? [];
          return content
              .map((e) => PayrollRecord.fromJson(e as Map<String, dynamic>))
              .toList();
        }
        return [];
      },
    );
  }

  /// Downloads the employee's own payslip as raw PDF bytes.
  /// Backend: `GET /api/payrolls/my/{id}/payslip` → `application/pdf`.
  Future<Uint8List> downloadMyPayslip(int payrollId) {
    return _api.getBytes('/api/payrolls/my/$payrollId/payslip');
  }
}
