class PayrollRecord {
  final int id;
  final int employeeId;
  final String employeeName;
  final int month;
  final int year;
  final double basicSalary;
  final double grossEarnings;
  final double totalDeductions;
  final double taxAmount;
  final double netSalary;
  final int workingDays;
  final int presentDays;
  final int leaveDays;
  final int payableDays;
  final String status;
  final String? paymentDate;

  PayrollRecord({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.month,
    required this.year,
    required this.basicSalary,
    required this.grossEarnings,
    required this.totalDeductions,
    required this.taxAmount,
    required this.netSalary,
    required this.workingDays,
    required this.presentDays,
    required this.leaveDays,
    required this.payableDays,
    required this.status,
    required this.paymentDate,
  });

  factory PayrollRecord.fromJson(Map<String, dynamic> j) => PayrollRecord(
        id: (j['id'] as num).toInt(),
        employeeId: (j['employeeId'] as num).toInt(),
        employeeName: j['employeeName'] as String? ?? '',
        month: (j['month'] as num).toInt(),
        year: (j['year'] as num).toInt(),
        basicSalary: (j['basicSalary'] as num? ?? 0).toDouble(),
        grossEarnings: (j['grossEarnings'] as num? ?? 0).toDouble(),
        totalDeductions: (j['totalDeductions'] as num? ?? 0).toDouble(),
        taxAmount: (j['taxAmount'] as num? ?? 0).toDouble(),
        netSalary: (j['netSalary'] as num? ?? 0).toDouble(),
        workingDays: (j['workingDays'] as num? ?? 0).toInt(),
        presentDays: (j['presentDays'] as num? ?? 0).toInt(),
        leaveDays: (j['leaveDays'] as num? ?? 0).toInt(),
        payableDays: (j['payableDays'] as num? ?? 0).toInt(),
        status: j['status'] as String? ?? '',
        paymentDate: j['paymentDate'] as String?,
      );
}
