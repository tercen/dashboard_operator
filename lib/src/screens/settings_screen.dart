import 'package:flutter/material.dart';
import 'package:sci_tercen_client/sci_client.dart' as sci;

import '../data.dart';
import '../widgets.dart';

class SettingsSnapshot {
  final Map<String, String> config;
  final sci.Version tercen;
  final sci.Version? sarno;
  final SchedulerStatus? scheduler;

  SettingsSnapshot(this.config, this.tercen, this.sarno, this.scheduler);
}

/// Read-only settings and versions (spec §7.8). Secrets are dropped
/// server-side, so nothing sensitive reaches this page to be hidden.
class SettingsScreen extends StatelessWidget {
  final DashboardData data;
  const SettingsScreen({super.key, required this.data});

  Future<SettingsSnapshot> _load() async {
    final results = await Future.wait([
      data.configSummary(),
      data.tercenVersion(),
      data.sarnoVersion().then<sci.Version?>((v) => v).catchError((_) => null),
      data
          .schedulerStatus()
          .then<SchedulerStatus?>((s) => s)
          .catchError((_) => null),
    ]);
    return SettingsSnapshot(
      results[0] as Map<String, String>,
      results[1] as sci.Version,
      results[2] as sci.Version?,
      results[3] as SchedulerStatus?,
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshingPanel<SettingsSnapshot>(
      title: 'Settings',
      interval: const Duration(minutes: 10),
      load: _load,
      builder: (context, snap, _) {
        String version(sci.Version? v) => v == null
            ? 'unreachable'
            : (v.tag.isNotEmpty ? v.tag : '${v.major}.${v.minor}.${v.patch}');

        final versions = <String, String>{
          'tercen': version(snap.tercen),
          if (snap.tercen.commit.isNotEmpty) 'commit': snap.tercen.commit,
          if (snap.tercen.date.isNotEmpty) 'built': formatDate(snap.tercen.date),
          'sarno': version(snap.sarno),
          'scheduler': snap.scheduler?.schedulerVersion ?? 'unreachable',
        };

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Versions', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _Table(values: versions),
              const SizedBox(height: 28),
              Text('Configuration',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Read-only. Secrets are never sent: the server returns an '
                'allowlist, so a newly added key is withheld by default.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
              const SizedBox(height: 8),
              _Table(values: snap.config),
            ],
          ),
        );
      },
    );
  }
}

class _Table extends StatelessWidget {
  final Map<String, String> values;
  const _Table({required this.values});

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return Text('Nothing reported.',
          style: Theme.of(context).textTheme.bodySmall);
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 780),
      child: Column(
        children: [
          for (final entry in values.entries)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color: Theme.of(context).colorScheme.outline)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 300,
                    child: Text(entry.key,
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                  Expanded(
                    child: SelectableText(
                      entry.value.isEmpty ? '—' : entry.value,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
