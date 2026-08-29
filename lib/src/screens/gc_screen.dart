import 'package:flutter/material.dart';

import '../data.dart';
import '../widgets.dart';

/// Garbage collector: what the `gc.phase` log lines have always said, as a
/// panel (spec §7.6). No actions — a mistimed manual GC run is an incident.
class GcScreen extends StatelessWidget {
  final DashboardData data;
  const GcScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return RefreshingPanel<Map<String, dynamic>>(
      title: 'Garbage collector',
      interval: const Duration(seconds: 30),
      load: data.gcStatus,
      builder: (context, status, _) {
        final isLeader = status['isLeader'] == true;
        final phases = ((status['phases'] as List?) ?? []).cast<Map>();
        final config = (status['config'] as Map?) ?? const {};
        final lastPhaseAt = '${status['lastPhaseAt'] ?? ''}';

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(spacing: 12, runSpacing: 12, children: [
                for (final tile in [
                  KpiTile(
                    label: 'This replica',
                    value: isLeader ? 'leader' : 'follower',
                    detail: isLeader
                        ? 'runs the GC phases'
                        : 'phases run elsewhere',
                    icon: Icons.workspace_premium_outlined,
                  ),
                  KpiTile(
                    label: 'Last phase',
                    value: lastPhaseAt.isEmpty
                        ? 'none yet'
                        : formatDate(lastPhaseAt),
                    detail: '${phases.length} recent phases',
                    icon: Icons.schedule,
                  ),
                  KpiTile(
                    label: 'Failures',
                    value: '${phases.where((p) => p['error'] != null).length}',
                    detail: 'in the recent window',
                    icon: Icons.error_outline,
                    valueColor: phases.any((p) => p['error'] != null)
                        ? StateChip.colorsFor(context, Severity.bad).$2
                        : null,
                  ),
                ])
                  SizedBox(width: 215, child: tile),
              ]),
              const SizedBox(height: 24),
              Text('Configuration',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              _KeyValues(values: {
                for (final entry in config.entries)
                  '${entry.key}': '${entry.value}',
              }),
              const SizedBox(height: 24),
              Text('Recent phases',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              if (phases.isEmpty)
                Text(
                  isLeader
                      ? 'No phase has run since this replica started.'
                      : 'This replica does not hold the GC lease, so it has '
                          'no phases to report.',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('PHASE')),
                      DataColumn(label: Text('DOMAIN')),
                      DataColumn(label: Text('AT')),
                      DataColumn(label: Text('ELAPSED'), numeric: true),
                      DataColumn(label: Text('RSS'), numeric: true),
                      DataColumn(label: Text('Δ RSS'), numeric: true),
                      DataColumn(label: Text('')),
                    ],
                    rows: [
                      for (final phase in phases.take(40))
                        DataRow(cells: [
                          DataCell(Text('${phase['phase']}')),
                          DataCell(Text('${phase['domain']}'.isEmpty
                              ? 'default'
                              : '${phase['domain']}')),
                          DataCell(Text(formatDate('${phase['at']}'))),
                          DataCell(Text('${phase['elapsedMs']} ms')),
                          DataCell(Text('${phase['rssMi']} Mi')),
                          DataCell(Text(
                              '${(phase['rssDeltaMi'] as num) >= 0 ? '+' : ''}'
                              '${phase['rssDeltaMi']} Mi')),
                          DataCell(phase['error'] == null
                              ? const SizedBox.shrink()
                              : Tooltip(
                                  message: '${phase['error']}',
                                  child: const StateChip('FailedState'),
                                )),
                        ]),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _KeyValues extends StatelessWidget {
  final Map<String, String> values;
  const _KeyValues({required this.values});

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return Text('No configuration reported.',
          style: Theme.of(context).textTheme.bodySmall);
    }
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        for (final entry in values.entries)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outline),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(entry.key,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(width: 8),
              Text(entry.value,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12.5)),
            ]),
          ),
      ],
    );
  }
}
