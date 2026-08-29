import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chart.dart';
import '../platform/platform_stub.dart'
    if (dart.library.js_interop) '../platform/platform_web.dart' as platform;
import '../data.dart';
import '../usage.dart';
import '../widgets.dart';

/// Manager dashboard: how much the organization actually used Tercen
/// (spec §8.2). Scoped server-side to the caller's domain.
class UsageScreen extends StatefulWidget {
  final DashboardData data;
  const UsageScreen({super.key, required this.data});

  @override
  State<UsageScreen> createState() => _UsageScreenState();
}

class _UsageScreenState extends State<UsageScreen> {
  late UsagePeriod _period = _periodFromUrl();
  late String _scope = _scopeFromUrl();

  /// Report links are shareable: `?section=usage&period=lastYear&scope=user`.
  UsagePeriod _periodFromUrl() {
    final wanted = platform.readUrlParam('period');
    return UsagePeriod.values.firstWhere((p) => p.name == wanted,
        orElse: () => UsagePeriod.thisMonth);
  }

  String _scopeFromUrl() {
    final wanted = platform.readUrlParam('scope');
    return (wanted == 'user' || wanted == 'team') ? wanted : 'team';
  }

  Future<(UsageReport, UsageReport)> _load() async {
    final (from, to) = _period.range();
    final (prevFrom, prevTo) = _period.previousRange();
    final results = await Future.wait([
      widget.data.usageReport(
          scope: _scope, from: from, to: to, bucket: _period.bucket),
      // The previous window powers the trend deltas; a failure there must
      // not cost us the current numbers.
      widget.data
          .usageReport(
              scope: _scope,
              from: prevFrom,
              to: prevTo,
              bucket: _period.bucket)
          .catchError((_) => UsageReport.empty),
    ]);
    return (results[0], results[1]);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshingPanel<(UsageReport, UsageReport)>(
      // Usage is a reporting view, not a live one.
      interval: const Duration(minutes: 5),
      key: ValueKey('$_period$_scope'),
      title: 'Usage',
      load: _load,
      actions: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'team', label: Text('By team')),
            ButtonSegment(value: 'user', label: Text('By user')),
          ],
          selected: {_scope},
          onSelectionChanged: (s) {
            setState(() => _scope = s.first);
            platform.setUrlParam('scope', _scope);
          },
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
        ),
        const SizedBox(width: 12),
        DropdownButton<UsagePeriod>(
          value: _period,
          underline: const SizedBox.shrink(),
          onChanged: (p) {
            setState(() => _period = p ?? _period);
            platform.setUrlParam('period', _period.name);
          },
          items: [
            for (final period in UsagePeriod.values)
              DropdownMenuItem(value: period, child: Text(period.label)),
          ],
        ),
        const SizedBox(width: 8),
      ],
      builder: (context, reports, _) {
        final (report, previous) = reports;
        final buckets = report.byBucket();
        final byId = report.byId();

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kpis(context, report, previous),
              const SizedBox(height: 28),
              Row(children: [
                Text('Runs over time',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text('${report.from} → ${report.to}',
                    style: Theme.of(context).textTheme.bodySmall),
              ]),
              const SizedBox(height: 10),
              RunsBarChart(rows: buckets, formatBucket: _formatBucket),
              const SizedBox(height: 28),
              Row(children: [
                Text(_scope == 'team' ? 'By team' : 'By user',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _copyCsv(context, byId),
                  icon: const Icon(Icons.copy_all_outlined, size: 17),
                  label: const Text('Copy as CSV'),
                ),
              ]),
              const SizedBox(height: 6),
              _breakdown(context, byId, report.runs),
            ],
          ),
        );
      },
    );
  }

  Widget _kpis(
      BuildContext context, UsageReport report, UsageReport previous) {
    String trend(num now, num before) {
      if (before == 0) return before == now ? 'no change' : 'no prior data';
      final delta = ((now - before) / before) * 100;
      final sign = delta >= 0 ? '+' : '';
      return '$sign${delta.toStringAsFixed(0)}% vs previous';
    }

    final hours = report.computeSeconds / 3600;
    final failing = report.failureRate > 10;

    return Wrap(spacing: 12, runSpacing: 12, children: [
      for (final tile in [
        KpiTile(
          label: 'Analyses run',
          value: '${report.runs}',
          detail: trend(report.runs, previous.runs),
          icon: Icons.play_circle_outline,
        ),
        KpiTile(
          label: 'Compute time',
          value: hours >= 1
              ? '${hours.toStringAsFixed(1)} h'
              : '${(report.computeSeconds / 60).toStringAsFixed(0)} min',
          detail: trend(report.computeSeconds, previous.computeSeconds),
          icon: Icons.timer_outlined,
        ),
        KpiTile(
          label: 'Failure rate',
          value: '${report.failureRate.toStringAsFixed(1)}%',
          detail: '${report.failed} of ${report.runs} runs',
          icon: Icons.error_outline,
          valueColor: failing
              ? StateChip.colorsFor(context, Severity.bad).$2
              : null,
        ),
        KpiTile(
          label: _scope == 'team' ? 'Active teams' : 'Active users',
          value: '${report.activeIds}',
          detail: 'ran at least one analysis',
          icon: _scope == 'team' ? Icons.workspaces_outline : Icons.group,
        ),
      ])
        SizedBox(width: 215, child: tile),
    ]);
  }

  Widget _breakdown(BuildContext context, List<UsageRow> rows, int totalRuns) {
    if (rows.isEmpty) {
      return Text('No activity in this period.',
          style: Theme.of(context).textTheme.bodySmall);
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [
          DataColumn(label: Text(_scope == 'team' ? 'TEAM' : 'USER')),
          const DataColumn(label: Text('RUNS'), numeric: true),
          const DataColumn(label: Text('SHARE'), numeric: true),
          const DataColumn(label: Text('FAILED'), numeric: true),
          const DataColumn(label: Text('COMPUTE'), numeric: true),
        ],
        rows: [
          for (final row in rows.take(25))
            DataRow(cells: [
              DataCell(Text(row.id.isEmpty ? '—' : row.id)),
              DataCell(Text('${row.n}')),
              DataCell(Text(totalRuns == 0
                  ? '—'
                  : '${(row.n / totalRuns * 100).toStringAsFixed(1)}%')),
              DataCell(row.failed == 0
                  ? const Text('0')
                  : Text('${row.failed}',
                      style: TextStyle(
                          color:
                              StateChip.colorsFor(context, Severity.bad).$2))),
              DataCell(Text(formatDuration(row.duration))),
            ]),
        ],
      ),
    );
  }

  String _formatBucket(String label) {
    // day/week labels are YYYY-MM-DD, month labels YYYY-MM.
    if (label.length == 10) return label.substring(5);
    if (label.length == 7) return label;
    return label;
  }

  Future<void> _copyCsv(BuildContext context, List<UsageRow> rows) async {
    final scopeHeader = _scope == 'team' ? 'team' : 'user';
    final csv = StringBuffer('$scopeHeader,runs,failed,compute_seconds\n');
    for (final row in rows) {
      csv.writeln('${_csv(row.id)},${row.n},${row.failed},'
          '${row.duration.toStringAsFixed(3)}');
    }
    await Clipboard.setData(ClipboardData(text: csv.toString()));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${rows.length} rows copied as CSV'), width: 260));
    }
  }

  String _csv(String value) =>
      value.contains(',') ? '"${value.replaceAll('"', '""')}"' : value;
}
