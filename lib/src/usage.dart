/// Usage rollup returned by `api/v1/usage/getUsageReport` (spec §8.3).
class UsageReport {
  final String scope;
  final String from;
  final String to;
  final String bucket;
  final String domain;
  final List<UsageRow> rows;

  const UsageReport({
    required this.scope,
    required this.from,
    required this.to,
    required this.bucket,
    required this.domain,
    required this.rows,
  });

  static const empty = UsageReport(
      scope: 'team', from: '', to: '', bucket: 'day', domain: '', rows: []);

  factory UsageReport.fromJson(Map<String, dynamic> m) => UsageReport(
        scope: '${m['scope'] ?? ''}',
        from: '${m['from'] ?? ''}',
        to: '${m['to'] ?? ''}',
        bucket: '${m['bucket'] ?? ''}',
        domain: '${m['domain'] ?? ''}',
        rows: ((m['rows'] as List?) ?? [])
            .map((r) => UsageRow.fromJson(r as Map<String, dynamic>))
            .toList(),
      );

  int get runs => rows.fold(0, (sum, r) => sum + r.n);
  int get failed => rows.fold(0, (sum, r) => sum + r.failed);
  double get computeSeconds => rows.fold(0.0, (sum, r) => sum + r.duration);

  /// Distinct ids that ran at least once — active teams, or active users.
  int get activeIds => rows.where((r) => r.n > 0).map((r) => r.id).toSet().length;

  double get failureRate => runs == 0 ? 0 : (failed / runs) * 100;

  /// Totals per bucket label, ordered by label (labels are ISO-ish, so
  /// lexicographic order is chronological).
  List<UsageRow> byBucket() {
    final folded = <String, UsageRow>{};
    for (final row in rows) {
      folded.update(row.bucket, (r) => r.merge(row),
          ifAbsent: () => row.copyWith(id: ''));
    }
    final result = folded.values.toList()
      ..sort((a, b) => a.bucket.compareTo(b.bucket));
    return result;
  }

  /// Totals per id across the period, largest first.
  List<UsageRow> byId() {
    final folded = <String, UsageRow>{};
    for (final row in rows) {
      folded.update(row.id, (r) => r.merge(row),
          ifAbsent: () => row.copyWith(bucket: ''));
    }
    final result = folded.values.toList()..sort((a, b) => b.n.compareTo(a.n));
    return result;
  }
}

class UsageRow {
  final String bucket;
  final String id;
  final int n;
  final double duration;
  final int failed;

  const UsageRow({
    required this.bucket,
    required this.id,
    required this.n,
    required this.duration,
    required this.failed,
  });

  factory UsageRow.fromJson(Map<String, dynamic> m) => UsageRow(
        bucket: '${m['bucket'] ?? ''}',
        id: '${m['id'] ?? ''}',
        n: (m['n'] as num?)?.toInt() ?? 0,
        duration: (m['duration'] as num?)?.toDouble() ?? 0,
        failed: (m['failed'] as num?)?.toInt() ?? 0,
      );

  UsageRow copyWith({String? bucket, String? id}) => UsageRow(
        bucket: bucket ?? this.bucket,
        id: id ?? this.id,
        n: n,
        duration: duration,
        failed: failed,
      );

  UsageRow merge(UsageRow other) => UsageRow(
        bucket: bucket,
        id: id,
        n: n + other.n,
        duration: duration + other.duration,
        failed: failed + other.failed,
      );
}

/// Period presets for the manager views.
enum UsagePeriod {
  thisWeek('This week', 7, 'day'),
  thisMonth('This month', 30, 'day'),
  last90('Last 90 days', 90, 'week'),
  lastYear('Last 12 months', 365, 'month');

  const UsagePeriod(this.label, this.days, this.bucket);

  final String label;
  final int days;
  final String bucket;

  /// Inclusive [from, to] as YYYY-MM-DD, in UTC.
  (String, String) range({DateTime? now}) {
    final today = (now ?? DateTime.now().toUtc());
    final to = DateTime.utc(today.year, today.month, today.day);
    final from = to.subtract(Duration(days: days - 1));
    return (_day(from), _day(to));
  }

  /// The period immediately before this one, for trend comparison.
  (String, String) previousRange({DateTime? now}) {
    final (fromIso, _) = range(now: now);
    final from = DateTime.parse(fromIso);
    final previousTo = from.subtract(const Duration(days: 1));
    final previousFrom = previousTo.subtract(Duration(days: days - 1));
    return (_day(previousFrom), _day(previousTo));
  }

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Whether a report window has already closed — its last day is behind us, so
/// no further run can land in it and its numbers are final.
///
/// `range()` always ends on today, so a current window is never closed.
/// `previousRange()` always ends the day before the current window starts, so
/// a comparison window always is. That asymmetry is what lets the Usage panel
/// fetch the comparison once instead of on every refresh tick.
bool isClosedWindow(String to, {DateTime? now}) =>
    to.compareTo(UsagePeriod._day((now ?? DateTime.now().toUtc()))) < 0;
