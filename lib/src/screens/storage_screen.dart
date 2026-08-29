import 'package:flutter/material.dart';

import '../data.dart';
import '../widgets.dart';

/// Storage accounting per team for the caller's domain (spec §7.5).
class StorageScreen extends StatelessWidget {
  final DashboardData data;
  const StorageScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return RefreshingPanel<Map<String, dynamic>>(
      title: 'Storage',
      interval: const Duration(minutes: 5),
      load: data.storageReport,
      builder: (context, report, _) {
        final teams = ((report['teams'] as List?) ?? []).cast<Map>();
        final total = teams.fold<double>(
            0, (sum, t) => sum + ((t['storageSize'] as num?)?.toDouble() ?? 0));
        final files = teams.fold<int>(
            0, (sum, t) => sum + ((t['fileCount'] as num?)?.toInt() ?? 0));
        final tables = teams.fold<int>(
            0, (sum, t) => sum + ((t['tableCount'] as num?)?.toInt() ?? 0));

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(spacing: 12, runSpacing: 12, children: [
                for (final tile in [
                  KpiTile(
                      label: 'Total stored',
                      value: formatBytes(total),
                      detail: 'across ${teams.length} teams',
                      icon: Icons.storage_outlined),
                  KpiTile(
                      label: 'Files',
                      value: '$files',
                      icon: Icons.description_outlined),
                  KpiTile(
                      label: 'Tables',
                      value: '$tables',
                      icon: Icons.table_chart_outlined),
                  KpiTile(
                      label: 'Domain',
                      value: '${report['domain']}'.isEmpty
                          ? 'default'
                          : '${report['domain']}',
                      icon: Icons.domain),
                ])
                  SizedBox(width: 215, child: tile),
              ]),
              const SizedBox(height: 24),
              if (teams.isEmpty)
                const Text('No teams in this domain.')
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('TEAM')),
                      DataColumn(label: Text('STORED'), numeric: true),
                      DataColumn(label: Text('SHARE'), numeric: true),
                      DataColumn(label: Text('TABLES'), numeric: true),
                      DataColumn(label: Text('FILES'), numeric: true),
                      DataColumn(label: Text('TASKS'), numeric: true),
                    ],
                    rows: [
                      for (final team in teams)
                        DataRow(cells: [
                          DataCell(Row(children: [
                            Text('${team['name']}'),
                            if (team['error'] != null) ...[
                              const SizedBox(width: 6),
                              Tooltip(
                                message: '${team['error']}',
                                child: Icon(Icons.warning_amber_outlined,
                                    size: 15,
                                    color: StateChip.colorsFor(
                                            context, Severity.warn)
                                        .$2),
                              ),
                            ],
                          ])),
                          DataCell(Text(formatBytes(
                              (team['storageSize'] as num?)?.toDouble() ?? 0))),
                          DataCell(Text(total == 0
                              ? '—'
                              : '${(((team['storageSize'] as num?)?.toDouble() ?? 0) / total * 100).toStringAsFixed(1)}%')),
                          DataCell(Text('${team['tableCount'] ?? '—'}')),
                          DataCell(Text('${team['fileCount'] ?? '—'}')),
                          DataCell(Text('${team['taskCount'] ?? '—'}')),
                        ]),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                'Accounted from the per-team summary view. Reconciliation '
                'against object-store actuals is spec §9.6 follow-up work.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ),
        );
      },
    );
  }
}
