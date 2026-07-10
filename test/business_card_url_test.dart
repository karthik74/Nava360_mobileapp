import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nava360/features/profile/business_card_screen.dart';

void main() {
  test('card URL round-trips the exact payload the hosted page expects', () {
    // The reference link shared for the feature — its data param decodes to
    // this JSON; our builder must produce a byte-identical payload.
    const referenceData =
        'eyJuYW1lIjoiU3VuaWwgS3VtYXIgSyIsImRlc2lnbmF0aW9uIjoiUmVnaW9uYWwgTWFuYWdlciAtSEwgJiBMQVAiLCJwaG9uZSI6Iis5MSAtIDcwMTk1MTYxMDMiLCJlbWFpbCI6InN1bmlsa3VtYXIua0BuYXZhY2hldGFuYWdyb3VwLmNvbSIsImxvY2F0aW9uIjoiTm8uMjAxLCAybmQgRmxvb3IsXG42MCBGZWV0IFJvYWQsIFNoYW5rYXIgTmFnYXIgTWFpbiBSb2FkLFxuTmFuZGluaSBMYXlvdXQsIEJlbmdhbHVydSAtIDU2MCAwOTYifQ==';

    final url = buildBusinessCardUrl(
      name: 'Sunil Kumar K',
      designation: 'Regional Manager -HL & LAP',
      phone: '+91 - 7019516103',
      email: 'sunilkumar.k@navachetanagroup.com',
      location:
          'No.201, 2nd Floor,\n60 Feet Road, Shankar Nagar Main Road,\nNandini Layout, Bengaluru - 560 096',
    );

    final data = Uri.parse(url).queryParameters['data'];
    expect(data, referenceData);
    // And it must decode back to valid JSON with the five expected keys.
    final decoded =
        jsonDecode(utf8.decode(base64Decode(data!))) as Map<String, dynamic>;
    expect(decoded.keys.toSet(),
        {'name', 'designation', 'phone', 'email', 'location'});
    expect(decoded['name'], 'Sunil Kumar K');
  });

  test('kannada and special characters survive the encoding', () {
    final url = buildBusinessCardUrl(
      name: 'ಸುನಿಲ್ ಕುಮಾರ್',
      designation: 'Manager & Lead',
      phone: '+91 98860 15737',
      email: 'x@y.com',
      location: 'ಬೆಂಗಳೂರು',
    );
    final data = Uri.parse(url).queryParameters['data'];
    final decoded =
        jsonDecode(utf8.decode(base64Decode(data!))) as Map<String, dynamic>;
    expect(decoded['name'], 'ಸುನಿಲ್ ಕುಮಾರ್');
    expect(decoded['designation'], 'Manager & Lead');
  });
}
