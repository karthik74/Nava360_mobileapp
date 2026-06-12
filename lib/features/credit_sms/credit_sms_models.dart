// Models for the consent-based credit-SMS tracking feature.
//
// Privacy note: the raw SMS body NEVER leaves the device. The parser produces a
// ParsedCreditSms with only extracted fields, a masked preview, and a one-way
// hash — that is all that is uploaded.

/// Current consent state for the logged-in employee (mirrors backend
/// `SmsConsentResponse`).
class CreditSmsConsent {
  final int? employeeId;
  final String consentStatus; // GRANTED | REVOKED
  final bool active;
  final String? consentGivenAt;
  final String? consentRevokedAt;
  final String? policyVersion;

  const CreditSmsConsent({
    required this.employeeId,
    required this.consentStatus,
    required this.active,
    this.consentGivenAt,
    this.consentRevokedAt,
    this.policyVersion,
  });

  factory CreditSmsConsent.fromJson(Map<String, dynamic> j) => CreditSmsConsent(
        employeeId: (j['employeeId'] as num?)?.toInt(),
        consentStatus: (j['consentStatus'] as String?) ?? 'REVOKED',
        active: j['active'] == true,
        consentGivenAt: j['consentGivenAt'] as String?,
        consentRevokedAt: j['consentRevokedAt'] as String?,
        policyVersion: j['policyVersion'] as String?,
      );
}

/// A detected credit as stored/returned by the backend (mirrors
/// `CreditSmsResponse`). Used for the employee's "Credits detected" list.
class CreditSms {
  final int id;
  final double? detectedAmount;
  final String? bankName;
  final String? referenceNo;
  final String? senderId;
  final String? smsReceivedAt;
  final String matchStatus; // UNMATCHED | MATCHED | IGNORED | ESCALATED
  final String riskLevel; // LOW | MEDIUM | HIGH
  final int? riskScore;
  final String? createdAt;

  const CreditSms({
    required this.id,
    required this.detectedAmount,
    required this.bankName,
    required this.referenceNo,
    required this.senderId,
    required this.smsReceivedAt,
    required this.matchStatus,
    required this.riskLevel,
    required this.riskScore,
    required this.createdAt,
  });

  factory CreditSms.fromJson(Map<String, dynamic> j) => CreditSms(
        id: (j['id'] as num).toInt(),
        detectedAmount: (j['detectedAmount'] as num?)?.toDouble(),
        bankName: j['bankName'] as String?,
        referenceNo: j['referenceNo'] as String?,
        senderId: j['senderId'] as String?,
        smsReceivedAt: j['smsReceivedAt'] as String?,
        matchStatus: (j['matchStatus'] as String?) ?? 'UNMATCHED',
        riskLevel: (j['riskLevel'] as String?) ?? 'LOW',
        riskScore: (j['riskScore'] as num?)?.toInt(),
        createdAt: j['createdAt'] as String?,
      );

  /// Human-friendly review state for the employee list.
  String get reviewLabel {
    switch (matchStatus) {
      case 'MATCHED':
        return 'Matched';
      case 'IGNORED':
        return 'Reviewed';
      case 'ESCALATED':
        return 'Under review';
      default:
        return 'Sent';
    }
  }
}

/// Parser output that is safe to upload (mirrors backend `CreditSmsRequest`).
/// Built entirely on-device from a single SMS; the raw text is discarded.
class ParsedCreditSms {
  final String? senderId;
  final DateTime smsReceivedAt;
  final double? detectedAmount;
  final String? referenceNo;
  final String? bankName;
  final String maskedSmsText;
  final String rawHash;
  final String source; // SMS | NOTIFICATION | MANUAL
  final double? latitude;
  final double? longitude;

  const ParsedCreditSms({
    required this.senderId,
    required this.smsReceivedAt,
    required this.detectedAmount,
    required this.referenceNo,
    required this.bankName,
    required this.maskedSmsText,
    required this.rawHash,
    this.source = 'SMS',
    this.latitude,
    this.longitude,
  });

  Map<String, dynamic> toJson() => {
        if (senderId != null) 'senderId': senderId,
        'smsReceivedAt': smsReceivedAt.toIso8601String(),
        if (detectedAmount != null) 'detectedAmount': detectedAmount,
        if (referenceNo != null) 'referenceNo': referenceNo,
        if (bankName != null) 'bankName': bankName,
        'maskedSmsText': maskedSmsText,
        'rawHash': rawHash,
        'source': source,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      };

  factory ParsedCreditSms.fromJson(Map<String, dynamic> j) => ParsedCreditSms(
        senderId: j['senderId'] as String?,
        smsReceivedAt: DateTime.parse(j['smsReceivedAt'] as String),
        detectedAmount: (j['detectedAmount'] as num?)?.toDouble(),
        referenceNo: j['referenceNo'] as String?,
        bankName: j['bankName'] as String?,
        maskedSmsText: j['maskedSmsText'] as String? ?? '',
        rawHash: j['rawHash'] as String,
        source: j['source'] as String? ?? 'SMS',
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
      );
}
