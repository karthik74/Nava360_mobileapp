import 'package:flutter_test/flutter_test.dart';
import 'package:nava360/features/auth/biometric/biometric_models.dart';

void main() {
  group('BiometricLoginResult', () {
    test('parses nested auth payload + rotated credential', () {
      final json = {
        'auth': {
          'token': 'jwt-abc',
          'tokenType': 'Bearer',
          'userId': 1,
          'username': 'emp001',
          'email': 'a@b.c',
          'role': 'EMPLOYEE',
          'employeeId': 5,
          'firstName': 'Ada',
          'lastName': 'L',
          'roles': ['EMPLOYEE'],
          'permissions': ['ATTENDANCE_VIEW'],
          'branchIds': [2, 3],
        },
        'biometricToken': 'rotated-token',
        'deviceId': 'dev-1',
        'expiresAt': '2026-10-01T10:00:00',
      };

      final res = BiometricLoginResult.fromJson(json);

      expect(res.auth.token, 'jwt-abc');
      expect(res.auth.username, 'emp001');
      expect(res.auth.employeeId, 5);
      expect(res.auth.permissions.contains('ATTENDANCE_VIEW'), isTrue);
      expect(res.biometricToken, 'rotated-token');
      expect(res.deviceId, 'dev-1');
    });
  });

  group('BiometricEnrollResult', () {
    test('parses token + deviceId', () {
      final res = BiometricEnrollResult.fromJson(
          {'biometricToken': 'raw-xyz', 'deviceId': 'dev-9'});
      expect(res.biometricToken, 'raw-xyz');
      expect(res.deviceId, 'dev-9');
    });
  });

  group('RegisteredDevice', () {
    test('parses fields incl. current-device flag and dates', () {
      final d = RegisteredDevice.fromJson({
        'id': 7,
        'deviceId': 'dev-1',
        'deviceName': 'Pixel 8',
        'platform': 'ANDROID',
        'enabled': true,
        'lastLoginAt': '2026-07-01T09:30:00',
        'createdAt': '2026-06-01T09:30:00',
        'expiresAt': '2026-09-29T09:30:00',
        'currentDevice': true,
      });
      expect(d.id, 7);
      expect(d.deviceName, 'Pixel 8');
      expect(d.platform, 'ANDROID');
      expect(d.enabled, isTrue);
      expect(d.currentDevice, isTrue);
      expect(d.lastLoginAt, isNotNull);
    });

    test('tolerates nulls for optional fields', () {
      final d = RegisteredDevice.fromJson({
        'id': 1,
        'deviceId': 'dev-2',
        'enabled': false,
        'currentDevice': false,
      });
      expect(d.deviceName, isNull);
      expect(d.lastLoginAt, isNull);
      expect(d.enabled, isFalse);
    });
  });
}
