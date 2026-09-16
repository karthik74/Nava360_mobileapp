import 'package:flutter_test/flutter_test.dart';
import 'package:nava360/features/profile/business_card_screen.dart';

/// Locks the vCard the QR encodes — same shape as the reference module's
/// generator (github.com/Raghunandan1157/digital-business-card), with the
/// organisation/website injected from branding instead of hardcoded.
void main() {
  test('vCard matches the reference generator shape', () {
    final v = buildVCard(
      name: 'Sunil Kumar K',
      designation: 'Regional Manager -HL & LAP',
      phone: '+91 - 7019516103',
      email: 'sunilkumar.k@navachetanagroup.com',
      location: 'No.201, 2nd Floor,\n60 Feet Road,\nBengaluru - 560 096',
      organisation: 'Navachetana Livelihoods Private Limited',
      website: 'https://navachetanalivelihoods.com',
    );
    final lines = v.split('\n');
    expect(lines.first, 'BEGIN:VCARD');
    expect(lines.last, 'END:VCARD');
    expect(lines, contains('FN:Sunil Kumar K'));
    // N: last;first — matches the reference split.
    expect(lines, contains('N:K;Sunil Kumar;;;'));
    expect(lines, contains('TITLE:Regional Manager -HL & LAP'));
    expect(lines, contains('ORG:Navachetana Livelihoods Private Limited'));
    // Phone cleaned of spaces and dashes for tel: use.
    expect(lines, contains('TEL;TYPE=CELL:+917019516103'));
    expect(lines, contains('URL:https://navachetanalivelihoods.com'));
    // Address newlines flattened to comma-separated.
    expect(
        lines,
        contains(
            'ADR;TYPE=WORK:;;No.201, 2nd Floor,, 60 Feet Road,, Bengaluru - 560 096;;;;'));
  });

  test('single-word names and blank branding fields degrade gracefully', () {
    final v = buildVCard(
      name: 'Sunil',
      designation: 'Manager',
      phone: '9986015737',
      email: 'x@y.com',
      location: 'Bengaluru',
      organisation: '',
      website: '',
    );
    expect(v, contains('N:;Sunil;;;'));
    expect(v.contains('ORG:'), isFalse);
    expect(v.contains('URL:'), isFalse);
  });
}
