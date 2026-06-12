import 'package:flutter_test/flutter_test.dart';
import 'package:nava360/features/credit_sms/credit_sms_parser.dart';

void main() {
  group('CreditSmsParser.isCreditSms', () {
    test('detects a UPI credit', () {
      expect(
        CreditSmsParser.isCreditSms(
            'Rs.5000 credited to a/c XX1234 via UPI ref 123456789012. -HDFC Bank'),
        isTrue,
      );
    });

    test('rejects a debit message', () {
      expect(
        CreditSmsParser.isCreditSms(
            'Rs.2000 debited from a/c XX1234 for purchase. -ICICI'),
        isFalse,
      );
    });

    test('rejects an OTP message even if it has an amount', () {
      expect(
        CreditSmsParser.isCreditSms(
            'Your OTP for Rs.999 txn is 456123. Do not share.'),
        isFalse,
      );
    });

    test('rejects a non-financial message', () {
      expect(CreditSmsParser.isCreditSms('Hi, are we meeting at 5?'), isFalse);
    });

    test('detects a credit SMS that also mentions a debit card', () {
      // Many genuine credit alerts say "...not you? block your debit card".
      // The bare word "debit" must not exclude these.
      expect(
        CreditSmsParser.isCreditSms(
            'Rs.5000 credited to a/c XX1234 on 12-Jun. Not you? Block your debit card at hdfc.in'),
        isTrue,
      );
    });

    test('detects "deposited" and "received" credits', () {
      expect(
        CreditSmsParser.isCreditSms('INR 1,200 deposited in A/c **1234. -Axis'),
        isTrue,
      );
      expect(
        CreditSmsParser.isCreditSms(
            'Received Rs 500 from JOHN. UPI Ref 412345678901 -Paytm'),
        isTrue,
      );
    });

    test('still rejects an explicit debit', () {
      expect(
        CreditSmsParser.isCreditSms('Rs.2000 debited from a/c XX1234.'),
        isFalse,
      );
    });
  });

  group('CreditSmsParser.parse', () {
    test('extracts amount, reference, bank and masks numbers', () {
      final parsed = CreditSmsParser.parse(
        body:
            'INR 12,500.00 credited to A/c no 9876543210 on 12-06-26. UPI Ref 987654321012. Call 9123456780. -ICICI Bank',
        sender: 'VM-ICICIB',
        receivedAt: DateTime(2026, 6, 12, 14, 30),
      );

      expect(parsed, isNotNull);
      expect(parsed!.detectedAmount, 12500.00);
      expect(parsed.referenceNo, '987654321012');
      expect(parsed.bankName, 'ICICI Bank');
      // Raw account & mobile numbers must not survive masking.
      expect(parsed.maskedSmsText.contains('9876543210'), isFalse);
      expect(parsed.maskedSmsText.contains('9123456780'), isFalse);
      // Last-4 retained for reconciliation.
      expect(parsed.maskedSmsText.contains('3210'), isTrue);
      expect(parsed.rawHash.length, 64); // SHA-256 hex
    });

    test('returns null for a debit message', () {
      final parsed = CreditSmsParser.parse(
        body: 'Rs.300 debited from a/c XX1234.',
        sender: 'AX-SBI',
        receivedAt: DateTime(2026, 6, 12, 9, 0),
      );
      expect(parsed, isNull);
    });

    test('same message hashes identically (de-dupe stability)', () {
      const body = 'Rs.500 credited via IMPS ref ABCD1234. -AXIS';
      final t = DateTime(2026, 6, 12, 10, 15, 42);
      final a = CreditSmsParser.hashRaw(body, 'AX-AXISBK', t);
      final b = CreditSmsParser.hashRaw(body, 'AX-AXISBK',
          DateTime(2026, 6, 12, 10, 15, 9)); // same minute, different second
      expect(a, b);
    });
  });
}
