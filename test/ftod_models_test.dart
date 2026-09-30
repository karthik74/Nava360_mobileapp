import 'package:flutter_test/flutter_test.dart';
import 'package:nava360/features/ftod/ftod_models.dart';

void main() {
  group('formatting', () {
    test('rupees use Indian digit grouping in whole rupees', () {
      expect(ftodRupees(7250), '₹7,250');
      expect(ftodRupees(725000), '₹7,25,000');
      expect(ftodRupees(12345678), '₹1,23,45,678');
      expect(ftodRupees(7250.5), '₹7,251'); // HALF_UP, like the push text
      expect(ftodRupees(0), '₹0');
      expect(ftodRupees(null), '₹0');
    });

    test('dates render as "01 Sep" and API keys are zero-padded', () {
      final d = DateTime(2026, 9, 1);
      expect(ftodDay(d), '01 Sep');
      expect(ftodDay(null), '—');
      expect(ftodIsoDate(d), '2026-09-01');
      expect(ftodMonthKey(d), '2026-09');
      expect(ftodMonthLabel(d), 'September 2026');
    });

    test('month shifting crosses year boundaries', () {
      expect(ftodShiftMonth(DateTime(2026, 1, 1), -1), DateTime(2025, 12, 1));
      expect(ftodShiftMonth(DateTime(2026, 12, 1), 1), DateTime(2027, 1, 1));
    });

    test('branch label appends "Branch" unless already present', () {
      expect(ftodBranchLabel('Tumkur'), 'Tumkur Branch');
      expect(ftodBranchLabel('Sira branch'), 'Sira branch');
      expect(ftodBranchLabel('  '), '');
      expect(ftodBranchLabel(null), '');
    });

    test('percent is safe for zero demand and capped at 100', () {
      expect(ftodPercent(27000, 54000), 50);
      expect(ftodPercent(10, 0), 0);
      expect(ftodPercent(120, 100), 100);
    });
  });

  group('FtodStatus', () {
    test('parses API values and defaults unknowns to pending', () {
      expect(FtodStatus.parse('PAID_ON_TIME'), FtodStatus.paidOnTime);
      expect(FtodStatus.parse('paid_late'), FtodStatus.paidLate);
      expect(FtodStatus.parse('PARTIAL'), FtodStatus.partial);
      expect(FtodStatus.parse(null), FtodStatus.pending);
      expect(FtodStatus.parse('WHATEVER'), FtodStatus.pending);
    });
  });

  group('FtodDistribution', () {
    final json = {
      'month': '2026-09',
      'scope': 'BRANCH',
      'totals': {
        'customers': 12,
        'dueAmount': 54000,
        'collectedAmount': '49500.00',
        'paidOnTime': 6,
        'paidLate': 5,
        'partial': 1,
        'pending': 0,
      },
      'days': [
        {
          'dueDate': '2026-09-05',
          'customers': 0,
          'dueAmount': 0,
          'collectedAmount': 0,
          'collections': [],
        },
        {
          'dueDate': '2026-09-01',
          'customers': 12,
          'dueAmount': 54000,
          'collectedAmount': 49500,
          'paidOnTime': 6,
          'paidLate': 5,
          'partial': 1,
          'pending': 0,
          'collections': [
            {'date': '2026-09-05', 'customers': 2, 'amount': 9000},
            {'date': '2026-09-01', 'customers': 6, 'amount': 27000},
            {'date': '2026-09-04', 'customers': 3, 'amount': 13500},
          ],
        },
      ],
    };

    test('parses totals, scope and sorts due dates and collection days', () {
      final d = FtodDistribution.fromJson(json);
      expect(d.month, '2026-09');
      expect(d.scope, 'BRANCH');
      expect(d.showsOfficer, isTrue);
      expect(d.totals.customers, 12);
      expect(d.totals.collectedAmount, 49500);
      expect(d.totals.collectedPercent, 92);
      expect(d.totals.counts.total, 12);
      expect(d.days.map((e) => e.dueDate),
          [DateTime(2026, 9, 1), DateTime(2026, 9, 5)]);

      final first = d.days.first;
      expect(first.headline(), 'Due 01 Sep · 12 customers · EMI ₹54,000');
      expect(first.collections.map((c) => c.chipLabel()), [
        '01 Sep · 6 · ₹27,000',
        '04 Sep · 3 · ₹13,500',
        '05 Sep · 2 · ₹9,000',
      ]);
      expect(first.collections.map((c) => c.daysAfter(first.dueDate)),
          [0, 3, 4]);
      // The 1st → 4th/5th pattern: money that came in after the due date.
      expect(first.lateAmount, 22500);
      expect(d.dayFor(DateTime(2026, 9, 1)), same(first));
      expect(d.dayFor(DateTime(2026, 9, 2)), isNull);
    });

    test('field officer scope hides the officer name', () {
      final d = FtodDistribution.fromJson({'scope': 'fo'});
      expect(d.scope, 'FO');
      expect(d.showsOfficer, isFalse);
      expect(d.totals.customers, 0);
      expect(d.days, isEmpty);
    });

    test('singular customer wording', () {
      final day = FtodDueDay.fromJson(
          {'dueDate': '2026-09-10', 'customers': 1, 'dueAmount': 7250});
      expect(day.headline(), 'Due 10 Sep · 1 customer · EMI ₹7,250');
    });
  });

  group('FtodDue', () {
    final today = DateTime(2026, 9, 29, 18, 30);

    FtodDue due(Map<String, dynamic> extra) => FtodDue.fromJson({
          'id': 7,
          'customerName': 'Lakshmi Devi',
          'phone': '98450 12345',
          'accountId': 'AC1001',
          'branchName': 'Tumkur',
          'dueDate': '2026-09-01',
          'dueAmount': 7250,
          ...extra,
        });

    test('on time and paid late wording', () {
      expect(
          due({'status': 'PAID_ON_TIME', 'collectedAmount': 7250})
              .statusText(today),
          'On time');
      expect(
          due({'status': 'PAID_LATE', 'daysLate': 3, 'collectedAmount': 7250})
              .statusText(today),
          'Paid 3 days late');
      expect(
          due({'status': 'PAID_LATE', 'daysLate': 1}).statusText(today),
          'Paid 1 day late');
    });

    test('partial shows the balance still due', () {
      final d = due({
        'status': 'PARTIAL',
        'collectedAmount': 5250,
        'balance': 2000,
        'collections': [
          {'date': '2026-09-04', 'amount': 3250},
          {'date': '2026-09-01', 'amount': 2000},
        ],
      });
      expect(d.statusText(today), 'Partial — ₹2,000 due');
      expect(d.collectedLine(), 'Collected ₹5,250 of ₹7,250');
      expect(d.paymentsLine(), '01 Sep ₹2,000 · 04 Sep ₹3,250');
      expect(d.reference, 'AC1001');
    });

    test('balance falls back to due minus collected', () {
      final d = due({'status': 'PARTIAL', 'collectedAmount': 5000});
      expect(d.balance, 2250);
    });

    test('pending counts overdue days from today, not the stale server value',
        () {
      final d = due({'status': 'PENDING', 'daysLate': 5});
      expect(d.overdueDays(today), 28);
      expect(d.statusText(today), 'Pending — 28 days');
    });

    test('pending before or on the due date is not called overdue', () {
      expect(
          due({'status': 'PENDING', 'dueDate': '2026-09-29'}).statusText(today),
          'Due today');
      expect(
          due({'status': 'PENDING', 'dueDate': '2026-10-05'}).statusText(today),
          'Due 05 Oct');
    });
  });

  group('FtodDuePage', () {
    test('parses PageResponse', () {
      final p = FtodDuePage.fromJson({
        'content': [
          {'id': 1, 'customerName': 'A', 'status': 'PENDING'},
          {'id': 2, 'customerName': 'B', 'status': 'PAID_LATE'},
        ],
        'page': 0,
        'size': 2,
        'totalElements': 5,
        'totalPages': 3,
        'first': true,
        'last': false,
      });
      expect(p.items.map((e) => e.id), [1, 2]);
      expect(p.items.last.status, FtodStatus.paidLate);
      expect(p.totalElements, 5);
      expect(p.last, isFalse);
    });

    test('derives "last" from totalPages when the flag is absent', () {
      final p = FtodDuePage.fromJson(
          {'content': [], 'page': 2, 'totalPages': 3, 'totalElements': 0});
      expect(p.last, isTrue);
    });

    test('tolerates a bare list', () {
      final p = FtodDuePage.fromJson([
        {'id': 3, 'customerName': 'C'},
      ]);
      expect(p.items.single.customerName, 'C');
      expect(p.last, isTrue);
    });
  });
}
