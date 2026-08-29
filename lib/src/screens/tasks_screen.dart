import 'package:flutter/material.dart';
import 'package:sci_tercen_client/sci_client.dart' as sci;

import '../data.dart';
import '../widgets.dart';

class TasksScreen extends StatelessWidget {
  final DashboardData data;
  const TasksScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return RefreshingPanel<List<sci.Task>>(
      title: 'Tasks',
      interval: const Duration(seconds: 10),
      load: data.tasks,
      builder: (context, tasks, refresh) {
        if (tasks.isEmpty) {
          return const Center(child: Text('No live tasks.'));
        }
        final sorted = [...tasks]..sort(
            (a, b) => b.createdDate.value.compareTo(a.createdDate.value));
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: DataTable(
              headingTextStyle: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(letterSpacing: 0.6),
              columns: const [
                DataColumn(label: Text('KIND')),
                DataColumn(label: Text('STATE')),
                DataColumn(label: Text('OWNER')),
                DataColumn(label: Text('USER')),
                DataColumn(label: Text('DOMAIN')),
                DataColumn(label: Text('CREATED')),
                DataColumn(label: Text('DURATION')),
                DataColumn(label: Text('CPU')),
                DataColumn(label: Text('RAM')),
                DataColumn(label: Text('')),
              ],
              rows: [
                for (final task in sorted)
                  DataRow(cells: [
                    DataCell(Text(task.shortKind),
                        onTap: () => _showDetail(context, task)),
                    DataCell(StateChip(task.stateKind),
                        onTap: () => _showDetail(context, task)),
                    DataCell(Text(task.owner)),
                    DataCell(Text(task.aclContext.username)),
                    DataCell(Text(task.aclContext.domain.isEmpty
                        ? 'default'
                        : task.aclContext.domain)),
                    DataCell(Text(formatDate(task.createdDate.value))),
                    DataCell(Text(formatDuration(task.duration))),
                    DataCell(Text(task.bookedCpu.isEmpty ? '—' : task.bookedCpu)),
                    DataCell(Text(task.bookedRam.isEmpty
                        ? '—'
                        : formatBytes(
                            double.tryParse(task.bookedRam) ?? 0))),
                    DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'Details',
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _showDetail(context, task),
                        icon: const Icon(Icons.info_outline),
                      ),
                      if (task.stateKind == 'RunningState' ||
                          task.stateKind == 'PendingState' ||
                          task.stateKind == 'InitState')
                        IconButton(
                          tooltip: 'Cancel task',
                          iconSize: 18,
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              _confirmCancel(context, task, refresh),
                          icon: const Icon(Icons.cancel_outlined),
                        ),
                    ])),
                  ]),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmCancel(
      BuildContext context, sci.Task task, VoidCallback refresh) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel task?'),
        content: Text(
            '${task.shortKind} owned by ${task.owner} (${task.id}).\n'
            'Cancel cascades to dependent tasks.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep running')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cancel task')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await data.cancelTask(task.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Cancel failed: $e')));
      }
      return;
    }
    refresh();
  }

  void _showDetail(BuildContext context, sci.Task task) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Expanded(
                      child: Text(task.kind,
                          style: Theme.of(context).textTheme.titleLarge)),
                  StateChip(task.stateKind),
                  const SizedBox(width: 8),
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close)),
                ]),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _row('Task id', CopyableId(task.id)),
                        _row('Owner', Text(task.owner)),
                        _row('User',
                            Text('${task.aclContext.username}'
                                '@${task.aclContext.domain.isEmpty ? "default" : task.aclContext.domain}')),
                        _row('Created',
                            Text(formatDate(task.createdDate.value))),
                        _row('Run', Text(formatDate(task.runDate.value))),
                        _row('Duration',
                            Text(formatDuration(task.duration))),
                        if (task.taskHash.isNotEmpty)
                          _row('Hash', CopyableId(task.taskHash)),
                        if (task.failureError.isNotEmpty)
                          _row(
                              'Error',
                              SelectableText(task.failureError,
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error))),
                        if (task.failureReason.isNotEmpty)
                          _row('Reason',
                              SelectableText(task.failureReason)),
                        if (task.environment.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text('Environment',
                              style:
                                  Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 4),
                          for (final pair in task.environment)
                            _row(pair.key, SelectableText(pair.value)),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  if (task.stdOutFileId.isNotEmpty)
                    TextButton.icon(
                      onPressed: () =>
                          _showLog(context, 'stdout', task.stdOutFileId),
                      icon: const Icon(Icons.article_outlined, size: 18),
                      label: const Text('stdout'),
                    ),
                  if (task.stdErrFileId.isNotEmpty)
                    TextButton.icon(
                      onPressed: () =>
                          _showLog(context, 'stderr', task.stdErrFileId),
                      icon: const Icon(Icons.report_outlined, size: 18),
                      label: const Text('stderr'),
                    ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(String label, Widget value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 120,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: value),
        ],
      ),
    );
  }

  void _showLog(BuildContext context, String name, String fileId) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(children: [
                  Text(name, style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close)),
                ]),
                Expanded(
                  child: FutureBuilder<String>(
                    future: data.readLog(fileId),
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return ErrorBox(error: snap.error!);
                      }
                      if (!snap.hasData) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: SingleChildScrollView(
                          child: SelectableText(
                            snap.data!.isEmpty ? '(empty)' : snap.data!,
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 12.5),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
