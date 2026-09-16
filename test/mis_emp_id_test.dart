import 'package:flutter_test/flutter_test.dart';
import 'package:nava360/features/mis/mis_auth.dart';

// XY12345 is a fictional placeholder code — no real employee id appears here.
void main() {
  test('misEmpIdFromIdentity resolves every identity shape seen in the field',
      () {
    // Clean code passes through.
    expect(misEmpIdFromIdentity(username: 'XY12345'), 'XY12345');
    // Lowercased code — the derived password must become XY@12345, not xy@12345.
    expect(misEmpIdFromIdentity(username: 'xy12345'), 'XY12345');
    // Email-shaped username (login accepts email) — local part wins.
    expect(misEmpIdFromIdentity(username: 'xy12345@noemail.local'), 'XY12345');
    // Separator variants.
    expect(misEmpIdFromIdentity(username: 'xy-12345'), 'XY12345');
    expect(misEmpIdFromIdentity(username: 'XY_12345'), 'XY12345');
    // Longer prefixes (other company codes) normalise the same way.
    expect(misEmpIdFromIdentity(username: 'abcd1234'), 'ABCD1234');
    // Username unusable → fall back to the email's local part.
    expect(
      misEmpIdFromIdentity(
          username: 'someone@gmail.com', email: 'xy12345@noemail.local'),
      'XY12345',
    );
    // Nothing code-shaped anywhere → trimmed username passes through.
    expect(misEmpIdFromIdentity(username: ' weird.user '), 'weird.user');
    // No identity at all.
    expect(misEmpIdFromIdentity(username: '', email: null), '');
  });

  test('deriveMisPassword mirrors the web derivation', () {
    expect(deriveMisPassword('XY12345'), 'XY@12345');
    expect(deriveMisPassword('XY'), 'XY');
  });
}
