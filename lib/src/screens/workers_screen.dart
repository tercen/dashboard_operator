import 'package:flutter/material.dart';
import 'package:sci_tercen_client/sci_client.dart' as sci;

import '../data.dart';
import '../widgets.dart';

class WorkersScreen extends StatelessWidget {
  final DashboardData data;
  const WorkersScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return RefreshingPanel<List<sci.Worker>>(
      title: 'Workers',
      interval: const Duration(seconds: 10),
      load: data.workers,
      builder: (context, workers, _) {
        if (workers.isEmpty) {
          return const Center(child: Text('No registered workers.'));
        }
        final sorted = [...workers]..sort((a, b) => a.name.compareTo(b.name));
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: DataTable(
              headingTextStyle: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(letterSpacing: 0.6),
              columns: const [
                DataColumn(label: Text('NAME')),
                DataColumn(label: Text('STATUS')),
                DataColumn(label: Text('CPU (FREE/TOTAL)')),
                DataColumn(label: Text('RAM (FREE/TOTAL)')),
                DataColumn(label: Text('THREADS')),
                DataColumn(label: Text('LAST ACTIVITY')),
                DataColumn(label: Text('URI')),
              ],
              rows: [
                for (final worker in sorted)
                  DataRow(cells: [
                    DataCell(Text(worker.name)),
                    DataCell(StateChip(worker.status)),
                    DataCell(Text('${worker.nAvailableThread}/${worker.nCPU}')),
                    DataCell(Text(
                        '${formatBytes(worker.availableMemory)} / ${formatBytes(worker.memory)}')),
                    DataCell(Text('${worker.nThread}')),
                    DataCell(Text(formatDate(worker.lastDateActivity))),
                    DataCell(Text(worker.uri,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12))),
                  ]),
              ],
            ),
          ),
        );
      },
    );
  }
}
