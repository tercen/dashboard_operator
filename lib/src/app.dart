import 'package:flutter/material.dart';

import 'data.dart';
import 'platform/platform_stub.dart'
    if (dart.library.js_interop) 'platform/platform_web.dart' as platform;
import 'screens/audit_screen.dart';
import 'screens/gc_screen.dart';
import 'screens/overview_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/storage_screen.dart';
import 'screens/tasks_screen.dart';
import 'screens/usage_screen.dart';
import 'screens/users_screen.dart';
import 'screens/workers_screen.dart';
import 'session.dart';
import 'theme.dart';

class DashboardApp extends StatefulWidget {
  final DashboardSession session;
  final Object? initError;

  const DashboardApp({super.key, required this.session, this.initError});

  @override
  State<DashboardApp> createState() => _DashboardAppState();
}

class _DashboardAppState extends State<DashboardApp> {
  final ThemeController _theme = ThemeController();

  @override
  void dispose() {
    _theme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _theme,
      builder: (context, mode, _) => MaterialApp(
        title: 'Tercen Dashboard',
        debugShowCheckedModeBanner: false,
        theme: DashboardTheme.light,
        darkTheme: DashboardTheme.dark,
        // Black is the default; the viewer's OS preference is deliberately
        // not consulted — an ops console should look the same everywhere.
        themeMode: mode,
        home: widget.initError != null
            ? _MessagePage(
                icon: Icons.link_off,
                title: 'No session',
                message: '${widget.initError}')
            : _RoleGate(session: widget.session, theme: _theme),
      ),
    );
  }
}

class _RoleGate extends StatelessWidget {
  final DashboardSession session;
  final ThemeController theme;
  const _RoleGate({required this.session, required this.theme});

  @override
  Widget build(BuildContext context) {
    if (session.isAdmin || session.isManager) {
      return DashboardShell(session: session, theme: theme);
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
  final ThemeController theme;
  const DashboardShell(
      {super.key, required this.session, required this.theme});

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  late final DashboardData _data = DashboardData(widget.session);
  int _index = 0;
  bool _restoredFromUrl = false;

  /// Sections available to this session. A manager without admin sees the
  /// usage views only — every admin endpoint would refuse them anyway.
  List<(IconData, IconData, String, Widget Function())> get _sections {
    final usage = (
      Icons.query_stats_outlined,
      Icons.query_stats,
      'Usage',
      () => UsageScreen(data: _data) as Widget,
    );
    if (!widget.session.isAdmin) return [usage];
    return [
      (
        Icons.dashboard_outlined,
        Icons.dashboard,
        'Overview',
        () => OverviewScreen(data: _data) as Widget
      ),
      usage,
      (
        Icons.checklist_outlined,
        Icons.checklist,
        'Tasks',
        () => TasksScreen(data: _data) as Widget
      ),
      (
        Icons.memory_outlined,
        Icons.memory,
        'Workers',
        () => WorkersScreen(data: _data) as Widget
      ),
      (
        Icons.group_outlined,
        Icons.group,
        'Users',
        () => UsersScreen(data: _data) as Widget
      ),
      (
        Icons.storage_outlined,
        Icons.storage,
        'Storage',
        () => StorageScreen(data: _data) as Widget
      ),
      (
        Icons.delete_sweep_outlined,
        Icons.delete_sweep,
        'GC',
        () => GcScreen(data: _data) as Widget
      ),
      (
        Icons.history_outlined,
        Icons.history,
        'Audit',
        () => AuditScreen(data: _data) as Widget
      ),
      (
        Icons.settings_outlined,
        Icons.settings,
        'Settings',
        () => SettingsScreen(data: _data) as Widget
      ),
    ];
  }

  /// Deep links: `?section=tasks` opens straight into a panel, so a triage
  /// URL can be pasted into an incident channel.
  void _restoreSection(List<(IconData, IconData, String, Widget Function())> sections) {
    if (_restoredFromUrl) return;
    _restoredFromUrl = true;
    final wanted = platform.readUrlParam('section').toLowerCase();
    if (wanted.isEmpty) return;
    final found =
        sections.indexWhere((s) => s.$3.toLowerCase() == wanted);
    if (found >= 0) _index = found;
  }

  void _select(
      int i, List<(IconData, IconData, String, Widget Function())> sections) {
    setState(() => _index = i);
    platform.setUrlParam('section', sections[i].$3.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final sections = _sections;
    _restoreSection(sections);
    final index = _index.clamp(0, sections.length - 1);

    // Mobile-friendly requirement (spec §7): on a phone the rail's icon
    // column would eat a third of the screen — use an app bar + drawer.
    final isNarrow = MediaQuery.sizeOf(context).width < 720;
    if (isNarrow) {
      return Scaffold(
        appBar: AppBar(
          title: Text(sections[index].$3),
          actions: [
            ValueListenableBuilder<ThemeMode>(
              valueListenable: widget.theme,
              builder: (context, _, __) => IconButton(
                tooltip: widget.theme.isDark
                    ? 'Switch to the white theme'
                    : 'Switch to the black theme',
                onPressed: widget.theme.toggle,
                icon: Icon(widget.theme.isDark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined),
              ),
            ),
          ],
        ),
        drawer: Drawer(
          child: SafeArea(
            child: ListView(
              children: [
                ListTile(
                  leading: Icon(Icons.hub,
                      color: Theme.of(context).colorScheme.primary),
                  title: const Text('Tercen Dashboard'),
                  subtitle: Text(
                      '${widget.session.username}@${widget.session.domain.isEmpty ? "default" : widget.session.domain}'),
                ),
                const Divider(),
                for (final (i, section) in sections.indexed)
                  ListTile(
                    leading: Icon(i == index ? section.$2 : section.$1),
                    title: Text(section.$3),
                    selected: i == index,
                    onTap: () {
                      Navigator.pop(context);
                      _select(i, sections);
                    },
                  ),
              ],
            ),
          ),
        ),
        body: sections[index].$4(),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: (i) => _select(i, sections),
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
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    ValueListenableBuilder<ThemeMode>(
                      valueListenable: widget.theme,
                      builder: (context, _, __) => IconButton(
                        tooltip: widget.theme.isDark
                            ? 'Switch to the white theme'
                            : 'Switch to the black theme',
                        onPressed: widget.theme.toggle,
                        icon: Icon(widget.theme.isDark
                            ? Icons.light_mode_outlined
                            : Icons.dark_mode_outlined),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Tooltip(
                      message:
                          '${widget.session.username}@${widget.session.domain.isEmpty ? "default" : widget.session.domain}',
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor:
                            Theme.of(context).colorScheme.primary,
                        child: Text(
                          widget.session.username.isEmpty
                              ? '?'
                              : widget.session.username[0].toUpperCase(),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onPrimary),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            destinations: [
              for (final (icon, selectedIcon, label, _) in sections)
                NavigationRailDestination(
                  icon: Icon(icon),
                  selectedIcon: Icon(selectedIcon),
                  label: Text(label),
                ),
            ],
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: sections[index].$4()),
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
