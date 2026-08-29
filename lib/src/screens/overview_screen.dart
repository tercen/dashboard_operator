import 'package:flutter/material.dart';
import 'package:sci_tercen_client/sci_client.dart' as sci;

import '../data.dart';
import '../widgets.dart';

class OverviewSnapshot {
  final sci.Version tercen;
  final sci.Version? sarno;
  final List<sci.Task> tasks;
  final List<sci.Worker> workers;

  OverviewSnapshot(this.tercen, this.sarno, this.tasks, this.workers);
}

class OverviewScreen extends StatelessWidget {
  final DashboardData data;
  const OverviewScreen({super.key, required this.data});

  Future<OverviewSnapshot> _load() async {
    final results = await Future.wait([
      data.tercenVersion(),
      // Sarno may be unreachable; the tile degrades on its own.
      data.sarnoVersion().then<sci.Version?>((v) => v).catchError((_) => null),
      data.tasks(),
      data.workers(),
    ]);
    return OverviewSnapshot(
      results[0] as sci.Version,
      results[1] as sci.Version?,
      (results[2] as List).cast<sci.Task>(),
      (results[3] as List).cast<sci.Worker>(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshingPanel<OverviewSnapshot>(
      title: 'Overview',
      interval: const Duration(seconds: 10),
      load: _load,
      builder: (context, snap, _) {
        final running = snap.tasks
            .where((t) => t.stateKind.startsWith('Running'))
            .length;
        final pending = snap.tasks
            .where((t) =>
                t.stateKind == 'PendingState' || t.stateKind == 'InitState')
            .length;
        final failed =
            snap.tasks.where((t) => t.stateKind == 'FailedState').length;
        final available =
            snap.workers.where((w) => w.status == 'Available').length;
        final domains =
            snap.tasks.map((t) => t.aclContext.domain).toSet().length;

        String version(sci.Version? v) => v == null
            ? 'unreachable'
            : (v.tag.isNotEmpty ? v.tag : '${v.major}.${v.minor}.${v.patch}');

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final tile in [
                    KpiTile(
                        label: 'Running tasks',
                        value: '$running',
                        detail: '$pending pending',
                        icon: Icons.play_circle_outline),
                    KpiTile(
                        label: 'Failed (live set)',
                        value: '$failed',
                        detail: failed > 0 ? 'see Tasks panel' : 'all clear',
                        icon: Icons.error_outline,
                        valueColor: failed > 0
                            ? Theme.of(context).colorScheme.error
                            : null),
                    KpiTile(
                        label: 'Workers',
                        value: '${snap.workers.length}',
                        detail: '$available available',
                        icon: Icons.memory),
                    KpiTile(
                        label: 'Active domains',
                        value: '$domains',
                        detail: 'with live tasks',
                        icon: Icons.domain),
                    KpiTile(
                        label: 'Tercen',
                        value: version(snap.tercen),
                        detail: snap.tercen.date.isNotEmpty
                            ? formatDate(snap.tercen.date)
                            : null,
                        icon: Icons.sell_outlined),
                    KpiTile(
                        label: 'Sarno',
                        value: version(snap.sarno),
                        icon: Icons.sell_outlined),
                  ])
                    SizedBox(width: 210, child: tile),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Live snapshot from the scheduler and version endpoints. '
                'Queue depth, GC state, storage and usage tiles land with the '
                'AdminService/UsageService backend work.',
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
