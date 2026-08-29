import 'package:flutter/material.dart';

import '../data.dart';
import '../widgets.dart';

class UsersScreen extends StatefulWidget {
  final DashboardData data;
  const UsersScreen({super.key, required this.data});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _RoleMenu extends StatelessWidget {
  final List<String> roles;
  final void Function(String role, bool grant) onChange;
  const _RoleMenu({required this.roles, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Change roles',
      icon: const Icon(Icons.edit_outlined, size: 15),
      padding: EdgeInsets.zero,
      onSelected: (role) => onChange(role, !roles.contains(role)),
      itemBuilder: (context) => [
        for (final role in _UsersScreenState._roles)
          PopupMenuItem(
            value: role,
            child: Row(children: [
              Icon(
                  roles.contains(role)
                      ? Icons.check_box_outlined
                      : Icons.check_box_outline_blank,
                  size: 17),
              const SizedBox(width: 8),
              Text(role),
            ]),
          ),
      ],
    );
  }
}

class _UsersScreenState extends State<UsersScreen> {
  String _filter = '';

  /// Grantable roles (the server enforces the same list). `user` is the
  /// baseline every account carries and is not offered here.
  static const _roles = ['manager', 'operator', 'admin'];

  Future<void> _changeRole(BuildContext context, DashboardUser user, String role,
      bool grant, VoidCallback refresh) async {
    try {
      final roles = await widget.data
          .changeRole(username: user.name, role: role, grant: grant);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${user.name}: ${roles.join(", ")}'), width: 320));
      }
      refresh();
    } catch (e) {
      if (context.mounted) {
        // The common refusal is a config-managed user, where the fix is to
        // edit tercen.roles — say so rather than showing a bare code.
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshingPanel<List<DashboardUser>>(
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
      builder: (context, users, refresh) {
        final visible = users
            .where((u) =>
                _filter.isEmpty ||
                u.name.toLowerCase().contains(_filter) ||
                u.email.toLowerCase().contains(_filter) ||
                u.domain.toLowerCase().contains(_filter))
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
                DataColumn(label: Text('DOMAIN')),
                DataColumn(label: Text('CREATED')),
              ],
              rows: [
                for (final user in visible)
                  DataRow(cells: [
                    DataCell(Text(user.name)),
                    DataCell(Text(user.email)),
                    DataCell(Row(children: [
                      Wrap(spacing: 4, children: [
                        for (final role in user.roles)
                          if (role != 'user') StateChip(role),
                      ]),
                      const SizedBox(width: 4),
                      _RoleMenu(
                        roles: user.roles,
                        onChange: (role, grant) =>
                            _changeRole(context, user, role, grant, refresh),
                      ),
                    ])),
                    DataCell(Icon(
                      user.isValidated
                          ? Icons.check_circle_outline
                          : Icons.hourglass_empty,
                      size: 18,
                      color: user.isValidated
                          ? StateChip.colorsFor(context, Severity.ok).$2
                          : Theme.of(context).colorScheme.outline,
                    )),
                    DataCell(Text(
                        user.domain.isEmpty ? 'default' : user.domain)),
                    DataCell(Text(formatDate(user.createdDate))),
                  ]),
              ],
            ),
          ),
        );
      },
    );
  }
}
