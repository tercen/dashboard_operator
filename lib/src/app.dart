import 'package:flutter/material.dart';

import 'data.dart';
import 'screens/overview_screen.dart';
import 'screens/tasks_screen.dart';
import 'screens/users_screen.dart';
import 'screens/workers_screen.dart';
import 'session.dart';

const _seed = Color(0xFF0E7490);

class DashboardApp extends StatelessWidget {
  final DashboardSession session;
  final Object? initError;

  const DashboardApp({super.key, required this.session, this.initError});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tercen Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: initError != null
          ? _MessagePage(
              icon: Icons.link_off,
              title: 'No session',
              message: '$initError')
          : _RoleGate(session: session),
    );
  }
}

class _RoleGate extends StatelessWidget {
  final DashboardSession session;
  const _RoleGate({required this.session});

  @override
  Widget build(BuildContext context) {
    if (session.isAdmin) {
      return DashboardShell(session: session);
    }
    if (session.isManager) {
      // Manager usage views arrive with the UsageService backend (spec §8).
      return const _MessagePage(
        icon: Icons.query_stats,
        title: 'Manager dashboard',
        message:
            'Usage views for your organization are coming here. '
            'The current release contains the admin panels only.',
      );
    }
    return const _MessagePage(
      icon: Icons.lock_outline,
      title: 'Not authorized',
      message:
          'The dashboard requires the admin or manager role. '
          'Ask your Tercen administrator for access.',
    );
  }
}

class DashboardShell extends StatefulWidget {
  final DashboardSession session;
  const DashboardShell({super.key, required this.session});

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  late final DashboardData _data = DashboardData(widget.session);
  int _index = 0;

  static const _sections = [
    (Icons.dashboard_outlined, Icons.dashboard, 'Overview'),
    (Icons.checklist_outlined, Icons.checklist, 'Tasks'),
    (Icons.memory_outlined, Icons.memory, 'Workers'),
    (Icons.group_outlined, Icons.group, 'Users'),
  ];

  @override
  Widget build(BuildContext context) {
    final screens = [
      OverviewScreen(data: _data),
      TasksScreen(data: _data),
      WorkersScreen(data: _data),
      UsersScreen(data: _data),
    ];
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 12),
              child: Column(children: [
                Icon(Icons.hub,
                    color: Theme.of(context).colorScheme.primary, size: 28),
                const SizedBox(height: 4),
                Text('Tercen',
                    style: Theme.of(context).textTheme.labelSmall),
              ]),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Tooltip(
                    message:
                        '${widget.session.username}@${widget.session.domain.isEmpty ? "default" : widget.session.domain}',
                    child: CircleAvatar(
                      radius: 14,
                      child: Text(
                        widget.session.username.isEmpty
                            ? '?'
                            : widget.session.username[0].toUpperCase(),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            destinations: [
              for (final (icon, selectedIcon, label) in _sections)
                NavigationRailDestination(
                  icon: Icon(icon),
                  selectedIcon: Icon(selectedIcon),
                  label: Text(label),
                ),
            ],
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: screens[_index]),
        ],
      ),
    );
  }
}

class _MessagePage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _MessagePage(
      {required this.icon, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}
