import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'credit_sms_models.dart';

/// Pure, on-device parsing of bank/payment SMS into a safe, masked
/// [ParsedCreditSms]. No network, no storage — deterministic and unit-testable.
///
/// Responsibilities:
///  1. Decide if a message is a *financial credit* (not a debit/OTP/promo).
///  2. Extract amount, reference/UTR, bank name.
///  3. Mask account & mobile numbers (keep only last 4 digits).
///  4. Produce a one-way SHA-256 hash of the raw text for de-duplication.
class CreditSmsParser {
  CreditSmsParser._();

  /// Words that indicate money came IN.
  static final RegExp _creditWords = RegExp(
    r'\b(credited|received|deposited|added to|a/?c\s+credited|account\s+credited)\b',
    caseSensitive: false,
  );

  /// Words that mean money went OUT — hard exclude (avoid false positives).
  /// Note: the bare word "debit" is intentionally NOT here — genuine credit SMS
  /// often mention "debit card", "block your debit card", etc., which would
  /// otherwise be wrongly excluded. We rely on the specific "debited" form.
  static final RegExp _debitWords = RegExp(
    r'\b(debited|withdrawn|spent|purchase|sent to|paid to|payment of)\b',
    caseSensitive: false,
  );

  /// OTP / promotional noise — exclude.
  static final RegExp _noiseWords = RegExp(
    r'\b(otp|one\s*time\s*password|do not share|offer|cashback reward|loan offer|pre-?approved)\b',
    caseSensitive: false,
  );

  /// ₹ / Rs / INR amount, e.g. "Rs. 12,500.00", "INR 500", "₹1,200".
  static final RegExp _amount = RegExp(
    r'(?:₹|rs\.?|inr)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  );

  /// UTR / reference / txn id, e.g. "Ref no 123456", "UTR: AXISP00123", "UPI Ref 987654321012".
  static final RegExp _reference = RegExp(
    r'(?:ref(?:erence)?(?:\s*no)?|utr|rrn|txn(?:\s*id)?|upi\s*ref(?:\s*no)?|imps\s*ref)\b[^A-Za-z0-9]{0,3}([A-Za-z0-9]{6,})',
    caseSensitive: false,
  );

  /// Known bank tokens → canonical name. Matched against sender id + body.
  static const Map<String, String> _banks = {
    'HDFC': 'HDFC Bank',
    'ICICI': 'ICICI Bank',
    'SBI': 'State Bank of India',
    'AXIS': 'Axis Bank',
    'KOTAK': 'Kotak Mahindra Bank',
    'YESBNK': 'Yes Bank',
    'YES BANK': 'Yes Bank',
    'PNB': 'Punjab National Bank',
    'BOB': 'Bank of Baroda',
    'CANARA': 'Canara Bank',
    'IDFC': 'IDFC First Bank',
    'INDUS': 'IndusInd Bank',
    'UNION': 'Union Bank',
    'FEDERAL': 'Federal Bank',
    'RBL': 'RBL Bank',
    'BANDHAN': 'Bandhan Bank',
    'AU': 'AU Small Finance Bank',
  };

  /// 6+ digit runs (account / card / mobile numbers) → keep last 4.
  static final RegExp _longDigits = RegExp(r'\d{6,}');

  /// Masked-style account refs like "A/c XX1234" or "ac no x1234".
  static final RegExp _accountRef = RegExp(
    r'(a/?c|acct?|account)\s*(no\.?|number|:)?\s*[xX*]+\d{2,4}',
    caseSensitive: false,
  );

  /// True if [body] looks like a genuine money-in (credit) message.
  static bool isCreditSms(String body) {
    if (body.isEmpty) return false;
    if (_noiseWords.hasMatch(body)) return false;
    if (_debitWords.hasMatch(body)) return false;
    final hasCredit = _creditWords.hasMatch(body);
    // A bare rail word ("UPI") alone isn't enough — require a credit word.
    return hasCredit && _amount.hasMatch(body);
  }

  /// Parse a credit SMS into the upload-safe shape. Returns null if it isn't a
  /// credit message (caller should skip it).
  static ParsedCreditSms? parse({
    required String body,
    required String? sender,
    required DateTime receivedAt,
    String source = 'SMS',
    double? latitude,
    double? longitude,
  }) {
    if (!isCreditSms(body)) return null;

    final amount = _extractAmount(body);
    final reference = _extractReference(body);
    final bank = _extractBank(sender, body);
    final masked = maskText(body);
    final hash = hashRaw(body, sender, receivedAt);

    return ParsedCreditSms(
      senderId: sender,
      smsReceivedAt: receivedAt,
      detectedAmount: amount,
      referenceNo: reference,
      bankName: bank,
      maskedSmsText: masked,
      rawHash: hash,
      source: source,
      latitude: latitude,
      longitude: longitude,
    );
  }

  static double? _extractAmount(String body) {
    final m = _amount.firstMatch(body);
    if (m == null) return null;
    final raw = m.group(1)!.replaceAll(',', '');
    return double.tryParse(raw);
  }

  static String? _extractReference(String body) {
    final m = _reference.firstMatch(body);
    return m?.group(1);
  }

  static String? _extractBank(String? sender, String body) {
    final hay = '${sender ?? ''} $body'.toUpperCase();
    for (final entry in _banks.entries) {
      if (hay.contains(entry.key)) return entry.value;
    }
    return null;
  }

  /// Replace account/card/mobile numbers with a masked form keeping last 4
  /// digits. Amounts (which carry ₹/Rs/commas) are left intact.
  static String maskText(String body) {
    var out = body.replaceAllMapped(_accountRef, (m) {
      final tail = RegExp(r'\d{2,4}$').firstMatch(m.group(0)!)?.group(0) ?? '';
      return 'A/c ••••$tail';
    });
    out = out.replaceAllMapped(_longDigits, (m) {
      final digits = m.group(0)!;
      final last4 = digits.length >= 4 ? digits.substring(digits.length - 4) : digits;
      return '••••$last4';
    });
    return out.trim();
  }

  /// One-way de-dupe key. Includes sender + minute-resolution timestamp so the
  /// same bank message re-read later hashes identically and is skipped.
  static String hashRaw(String body, String? sender, DateTime receivedAt) {
    final minute = DateTime(receivedAt.year, receivedAt.month, receivedAt.day,
            receivedAt.hour, receivedAt.minute)
        .toIso8601String();
    final input = '${sender ?? ''}|$minute|${body.trim()}';
    return sha256.convert(utf8.encode(input)).toString();
  }
}
