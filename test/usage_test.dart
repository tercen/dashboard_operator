import 'package:flutter_test/flutter_test.dart';

import 'package:tercen_dashboard/src/usage.dart';

UsageReport report(List<Map<String, dynamic>> rows) =>
    UsageReport.fromJson({
      'scope': 'team',
      'from': '2026-08-01',
      'to': '2026-08-03',
      'bucket': 'day',
      'domain': '',
      'rows': rows,
    });

void main() {
  group('UsageReport', () {
    final sample = report([
      {'bucket': '2026-08-01', 'id': 'alpha', 'n': 10, 'duration': 60.0, 'failed': 1},
      {'bucket': '2026-08-01', 'id': 'beta', 'n': 5, 'duration': 30.0, 'failed': 0},
      {'bucket': '2026-08-02', 'id': 'alpha', 'n': 5, 'duration': 10.0, 'failed': 4},
    ]);

    test('totals sum every row', () {
      expect(sample.runs, 20);
      expect(sample.failed, 5);
      expect(sample.computeSeconds, 100.0);
      expect(sample.failureRate, 25.0);
    });

    test('active ids are distinct', () {
      expect(sample.activeIds, 2);
    });

    test('byBucket folds ids away and stays chronological', () {
      final buckets = sample.byBucket();
      expect(buckets.map((b) => b.bucket), ['2026-08-01', '2026-08-02']);
      expect(buckets.first.n, 15);
      expect(buckets.first.failed, 1);
      expect(buckets.last.n, 5);
      // Folded rows must not keep one contributor's id.
      expect(buckets.first.id, '');
    });

    test('byId folds buckets away, largest first', () {
      final ids = sample.byId();
      expect(ids.map((r) => r.id), ['alpha', 'beta']);
      expect(ids.first.n, 15);
      expect(ids.first.failed, 5);
      expect(ids.first.duration, 70.0);
    });

    test('an empty report has no runs and no failure rate', () {
      expect(report([]).runs, 0);
      expect(report([]).failureRate, 0);
      expect(UsageReport.empty.runs, 0);
    });
  });

  group('UsagePeriod', () {
    final now = DateTime.utc(2026, 8, 29);

    test('this week is the 7 days ending today, inclusive', () {
      expect(UsagePeriod.thisWeek.range(now: now), ('2026-08-23', '2026-08-29'));
    });

    test('the previous window abuts without overlapping', () {
      final (from, to) = UsagePeriod.thisWeek.range(now: now);
      final (prevFrom, prevTo) = UsagePeriod.thisWeek.previousRange(now: now);
      expect(prevTo, '2026-08-22');
      expect(prevFrom, '2026-08-16');
      expect(DateTime.parse(prevTo).isBefore(DateTime.parse(from)), isTrue);
      expect(to, '2026-08-29');
    });

    test('longer periods bucket more coarsely', () {
      expect(UsagePeriod.thisMonth.bucket, 'day');
      expect(UsagePeriod.last90.bucket, 'week');
      expect(UsagePeriod.lastYear.bucket, 'month');
    });
  });
}
