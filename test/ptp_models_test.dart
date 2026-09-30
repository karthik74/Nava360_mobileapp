import 'package:flutter_test/flutter_test.dart';
import 'package:nava360/features/notifications/demo_alert_poller.dart';
import 'package:nava360/features/ptp/ptp_models.dart';
import 'package:nava360/features/ptp/ptp_providers.dart';
import 'package:nava360/features/ptp/ptp_repository.dart';

void main() {
  group('ptpRupees', () {
    test('uses Indian digit grouping, whole rupees', () {
      expect(ptpRupees(7250), '₹7,250');
      expect(ptpRupees(125000), '₹1,25,000');
      expect(ptpRupees(7249.6), '₹7,250');
    });
  });

  group('ptpBranchLabel', () {
    test('appends Branch unless already present', () {
      expect(ptpBranchLabel('Hubli'), 'Hubli Branch');
      expect(ptpBranchLabel('Hubli branch'), 'Hubli branch');
      expect(ptpBranchLabel('  '), isNull);
      expect(ptpBranchLabel(null), isNull);
    });
  });

  group('PtpFilter.fromApi', () {
    test('maps query values, defaults to All', () {
      expect(PtpFilter.fromApi('DUE_TODAY'), PtpFilter.dueToday);
      expect(PtpFilter.fromApi('broken'), PtpFilter.broken);
      expect(PtpFilter.fromApi(null), PtpFilter.all);
      expect(PtpFilter.fromApi('nonsense'), PtpFilter.all);
    });
  });

  group('ptpBadge', () {
    final now = DateTime(2026, 9, 29, 18, 30);
    CrmPtp open(DateTime d) =>
        CrmPtp(id: 1, status: 'OPEN', customerName: 'A', promisedDate: d);

    test('buckets OPEN promises against today', () {
      expect(ptpBadge(open(DateTime(2026, 9, 29)), now: now).label, 'Due today');
      expect(ptpBadge(open(DateTime(2026, 9, 30)), now: now).label, 'Due tomorrow');
      expect(ptpBadge(open(DateTime(2026, 10, 3)), now: now).label, 'Upcoming');
      expect(ptpBadge(open(DateTime(2026, 9, 27)), now: now).label, 'Overdue');
    });

    test('closed states win over dates', () {
      const broken = CrmPtp(id: 2, status: 'BROKEN', customerName: 'B');
      const kept = CrmPtp(id: 3, status: 'KEPT', customerName: 'C');
      expect(ptpBadge(broken, now: now).label, 'Broken');
      expect(ptpBadge(kept, now: now).label, 'Kept');
    });
  });

  test('CrmPtp.fromJson reads the backend DTO', () {
    final p = CrmPtp.fromJson({
      'id': 42,
      'status': 'OPEN',
      'module': 'FTOD',
      'promisedDate': '2026-09-30',
      'amount': 7250.00,
      'customerName': 'Lakshmi',
      'phone': '9876543210',
      'accountId': 'AC1',
      'branchName': 'Hubli',
      'officerText': 'RAVI K',
      'fieldOfficerName': null,
      'taskId': 9,
      'rescheduleCount': 1,
    });
    expect(p.promisedDate, DateTime(2026, 9, 30));
    expect(p.amount, 7250);
    expect(p.officerLabel, 'RAVI K');
    expect(p.taskId, 9);
  });

  test('PtpSummary parses scope and counts', () {
    final s = PtpSummary.fromJson({
      'scope': 'BRANCH',
      'all': 5,
      'dueToday': 2,
      'dueTomorrow': 1,
      'broken': 1,
      'upcoming': 1,
      'kept': 3,
      'dueTodayAmount': 14500,
    });
    expect(s.scope, PtpScope.branch);
    expect(s.countFor(PtpFilter.kept), 3);
    expect(s.dueTodayAmount, 14500);
  });

  test('notificationRoute honours in-app routes only', () {
    expect(notificationRoute({'route': '/ptp'}), '/ptp');
    expect(notificationRoute({'route': '/ftod'}), '/ftod');
    expect(notificationRoute({'route': null}), '/tasks');
    expect(notificationRoute({'route': 'https://evil.example'}), '/tasks');
    expect(notificationRoute({}), '/tasks');
  });

  test('a failed refresh keeps the rows and its error, even across load-more',
      () async {
    final repo = _FakePtpRepo();
    final n = PtpListNotifier(repo, PtpFilter.dueToday);
    await pumpEventQueue();
    expect(n.state.items.map((p) => p.id), [1]);
    expect(n.state.error, isNull);

    repo.failNext = true;
    await n.refresh();
    expect(n.state.items.map((p) => p.id), [1]); // stale rows stay on screen
    expect(n.state.error, isNotNull); // ...flagged, so the screen can say so

    await n.loadMore();
    expect(n.state.items.map((p) => p.id), [1, 2]);
    expect(n.state.error, isNotNull); // page 0 is still stale
    n.dispose();
  });
}

class _FakePtpRepo implements PtpRepository {
  bool failNext = false;

  @override
  Future<PtpPage> mine({
    required PtpFilter filter,
    int page = 0,
    int size = PtpRepository.pageSize,
  }) async {
    if (failNext) {
      failNext = false;
      throw Exception('offline');
    }
    return PtpPage(
      items: [CrmPtp.fromJson({'id': page + 1, 'status': 'OPEN'})],
      page: page,
      last: page >= 1,
      totalElements: 2,
    );
  }

  @override
  Future<PtpSummary> summary() => throw UnimplementedError();
}
