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

  group('closed windows (tercen/sci#1231)', () {
    final now = DateTime.utc(2026, 8, 29, 11, 30);

    test('a window ending before today is closed', () {
      expect(isClosedWindow('2026-08-28', now: now), isTrue);
      expect(isClosedWindow('2020-01-01', now: now), isTrue);
    });

    test('a window ending today is not closed — runs can still land in it', () {
      expect(isClosedWindow('2026-08-29', now: now), isFalse);
    });

    test('a window ending in the future is not closed', () {
      expect(isClosedWindow('2026-08-30', now: now), isFalse);
    });

    test('every period: the current window is open, the comparison is closed',
        () {
      // This asymmetry is what makes caching the comparison window safe. If
      // range()/previousRange() ever stop guaranteeing it, the Usage panel
      // would start serving a stale comparison — so pin it here rather than
      // in the screen.
      for (final period in UsagePeriod.values) {
        final (_, to) = period.range(now: now);
        final (_, prevTo) = period.previousRange(now: now);

        expect(isClosedWindow(to, now: now), isFalse,
            reason: '${period.name}: the current window must stay live');
        expect(isClosedWindow(prevTo, now: now), isTrue,
            reason: '${period.name}: the comparison window must be final');
      }
    });

    test('the boundary moves with UTC midnight', () {
      // Yesterday's comparison must not be reused once the day rolls over —
      // the cache is keyed by the request, and the request changes here.
      const to = '2026-08-29';
      expect(isClosedWindow(to, now: DateTime.utc(2026, 8, 29, 23, 59)), isFalse);
      expect(isClosedWindow(to, now: DateTime.utc(2026, 8, 30, 0, 1)), isTrue);
    });
  });
}
