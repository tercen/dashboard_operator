import 'package:flutter/material.dart';
import 'package:sci_tercen_client/sci_client.dart' as sci;

import '../data.dart';
import '../widgets.dart';

class UsersScreen extends StatefulWidget {
  final DashboardData data;
  const UsersScreen({super.key, required this.data});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    return RefreshingPanel<List<sci.User>>(
      title: 'Users',
      interval: const Duration(minutes: 2),
      load: widget.data.users,
      actions: [
        SizedBox(
          width: 240,
          child: TextField(
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Filter by name or email',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) =>
                setState(() => _filter = value.toLowerCase()),
          ),
        ),
        const SizedBox(width: 8),
      ],
      builder: (context, users, _) {
        final visible = users
            .where((u) =>
                _filter.isEmpty ||
                u.name.toLowerCase().contains(_filter) ||
                u.email.toLowerCase().contains(_filter))
            .toList();
        if (visible.isEmpty) {
          return const Center(child: Text('No matching users.'));
        }
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
                DataColumn(label: Text('EMAIL')),
                DataColumn(label: Text('ROLES')),
                DataColumn(label: Text('VALIDATED')),
                DataColumn(label: Text('CREATED')),
              ],
              rows: [
                for (final user in visible)
                  DataRow(cells: [
                    DataCell(Text(user.name)),
                    DataCell(Text(user.email)),
                    DataCell(Wrap(spacing: 4, children: [
                      for (final role in user.roles)
                        if (role != 'user') StateChip(role),
                    ])),
                    DataCell(Icon(
                      user.isValidated
                          ? Icons.check_circle_outline
                          : Icons.hourglass_empty,
                      size: 18,
                      color: user.isValidated
                          ? const Color(0xFF186A45)
                          : Theme.of(context).colorScheme.outline,
                    )),
                    DataCell(Text(formatDate(user.createdDate.value))),
                  ]),
              ],
            ),
          ),
        );
      },
    );
  }
}
