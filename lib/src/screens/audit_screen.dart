import 'package:flutter/material.dart';

import '../data.dart';
import '../widgets.dart';

/// Audit feed: what changed, across every domain (spec §7.7).
class AuditScreen extends StatefulWidget {
  final DashboardData data;
  const AuditScreen({super.key, required this.data});

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  String _filter = '';

  static const _typeSeverity = <String, Severity>{
    'create': Severity.ok,
    'delete': Severity.bad,
    'update': Severity.info,
    'rename': Severity.info,
    'changeUserPrivilege': Severity.warn,
    'changeProjectVisibility': Severity.warn,
    'cloneWorkflow': Severity.neutral,
  };

  @override
  Widget build(BuildContext context) {
    return RefreshingPanel<Map<String, dynamic>>(
      title: 'Audit',
      interval: const Duration(minutes: 1),
      load: () => widget.data.activities(limit: 200),
      actions: [
        SizedBox(
          width: 250,
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Filter by user, kind or name',
            ),
            onChanged: (v) => setState(() => _filter = v.toLowerCase()),
          ),
        ),
        const SizedBox(width: 8),
      ],
      builder: (context, report, _) {
        final rows = ((report['rows'] as List?) ?? [])
            .cast<Map>()
            .where((r) =>
                _filter.isEmpty ||
                '${r['userId']} ${r['objectKind']} ${r['name']} '
                        '${r['type']} ${r['projectName']}'
                    .toLowerCase()
                    .contains(_filter))
            .toList();

        if (rows.isEmpty) {
          return const Center(child: Text('No matching activity.'));
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: DataTable(
              columns: const [
                DataColumn(label: Text('WHEN')),
                DataColumn(label: Text('ACTION')),
                DataColumn(label: Text('KIND')),
                DataColumn(label: Text('NAME')),
                DataColumn(label: Text('USER')),
                DataColumn(label: Text('TEAM')),
                DataColumn(label: Text('DOMAIN')),
              ],
              rows: [
                for (final row in rows)
                  DataRow(cells: [
                    DataCell(Text(formatDate('${row['date']}'))),
                    DataCell(_ActionChip(
                      label: '${row['type']}',
                      severity:
                          _typeSeverity['${row['type']}'] ?? Severity.neutral,
                    )),
                    DataCell(Text('${row['objectKind']}')),
                    DataCell(ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Text('${row['name']}',
                          overflow: TextOverflow.ellipsis),
                    )),
                    DataCell(Text('${row['userId']}')),
                    DataCell(Text('${row['teamId']}')),
                    DataCell(Text('${row['domain']}'.isEmpty
                        ? 'default'
                        : '${row['domain']}')),
                  ]),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final Severity severity;
  const _ActionChip({required this.label, required this.severity});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = StateChip.colorsFor(context, severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label,
          style:
              TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w600)),
    );
  }
}
