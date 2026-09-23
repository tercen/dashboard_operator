import 'package:flutter/material.dart';

import '../data.dart';
import '../user_activity.dart';
import '../user_filters.dart';
import '../widgets.dart';
import 'create_user_dialog.dart';
import 'edit_tags_dialog.dart';
import 'tasks_screen.dart' show LinkText;

/// The count line above the table. [shown] is the number of rows left after
/// the filters. The total is the server's when it reports one; otherwise it
/// is the number of users loaded, and the line says the total is unknown.
/// It claims only what the response supports: a server that says the list is
/// truncated but gives no total has not said why, so the line does not blame
/// the limit.
///
/// [excluded] loaded users were left out by email domain: they leave every
/// count here. Of the users the server did not return, nobody knows how many
/// an exclusion would leave out, so a list with more to it is counted as
/// "the first N" and not against the server's total.
String showingBanner(UserListing listing, int shown, {int excluded = 0}) {
  final loaded = listing.users.length;
  final kept = loaded - excluded;
  final total = listing.total;
  final note =
      excluded == 0 ? '' : ' ($excluded excluded by email domain)';
  if (total != null) {
    if (!listing.mayHaveMore) {
      return 'Showing $shown of ${total - excluded} users$note';
    }
    return excluded == 0
        ? 'Showing $shown of $total users — the server returned only the '
            'first $loaded'
        : 'Showing $shown of the first $kept users$note — the server '
            'returned only the first $loaded of $total';
  }
  if (listing.truncated == true) {
    return 'Showing $shown of the first $kept users$note — the server '
        'reported the list as incomplete; it does not report a total';
  }
  return listing.mayHaveMore
      ? 'Showing $shown of the first $kept users$note — the list stopped at '
          'the limit of ${listing.limit}; this server does not report a total'
      : 'Showing $shown of $kept users loaded$note; this server does not '
          'report a total';
}

/// One page's worth of rows at a time, for [PaginatedDataTable].
class _UserRows extends DataTableSource {
  final List<DashboardUser> users;
  final DataRow Function(DashboardUser user) rowFor;
  _UserRows(this.users, this.rowFor);

  @override
  DataRow? getRow(int index) =>
      index < users.length ? rowFor(users[index]) : null;

  @override
  int get rowCount => users.length;

  @override
  bool get isRowCountApproximate => false;

  @override
  int get selectedRowCount => 0;
}

/// The Users page. Its filters — the activity window, the MAU preset and
/// the excluded email domains — are kept in [DashboardData.settings] and
/// restored on load.
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

/// The Projects owned cell: blank when the server does not send the count,
/// the count when it does, and "unknown" — muted and italic, so it never
/// reads as a number — when the server sent null because it could not count.
class _ProjectsOwned extends StatelessWidget {
  final DashboardUser user;
  const _ProjectsOwned(this.user);

  @override
  Widget build(BuildContext context) {
    if (!user.projectsOwnedReported) return const SizedBox.shrink();
    final count = user.projectsOwned;
    if (count != null) return Text('$count');
    return Tooltip(
      message: 'The server could not count the projects in this instance',
      child: Text('unknown',
          key: const Key('projects-owned-unknown'),
          style: TextStyle(
            fontStyle: FontStyle.italic,
            color: StateChip.colorsFor(context, Severity.neutral).$2,
          )),
    );
  }
}

/// A read-only tag: outlined, so it does not read as a role chip. Never
/// wider than [maxWidth]: a longer tag is cut with an ellipsis.
class _TagChip extends StatelessWidget {
  static const maxWidth = 80.0;
  final String tag;
  const _TagChip(this.tag, {super.key});

  @override
  Widget build(BuildContext context) {
    final fg = StateChip.colorsFor(context, Severity.neutral).$2;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: fg.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(tag,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: fg, fontSize: 11.5)),
      ),
    );
  }
}

/// The Tags cell, bounded whatever the server sends: the first [shown] tags
/// as chips, then "+N" for the rest. The full list is the cell's tooltip.
/// Two chips of 80 px keep a row with every role and a four-digit "+N"
/// inside a 1280 px screen (see the worst-case golden and its edge test).
class _Tags extends StatelessWidget {
  static const shown = 2;
  final List<String> tags;
  const _Tags(this.tags);

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    final hidden = tags.length - shown;
    return Tooltip(
      message: tags.join(', '),
      // A Row, not a Wrap: the column sizes to its cells, and a Wrap
      // measured that way stacks its chips.
      child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
        for (final tag in tags.take(shown)) _TagChip(tag),
        if (hidden > 0) _TagChip('+$hidden', key: const Key('tags-more')),
      ]),
    );
  }
}

/// Where the activity columns stand. They load beside the list, which
/// never waits for them: listUserActivity takes seconds.
enum _ActivityState { loading, loaded, failed, unavailable }

/// Muted text for what is not a value: "unknown", "none", the loading mark.
class _Muted extends StatelessWidget {
  final String text;
  final bool italic;
  const _Muted(this.text, {super.key, this.italic = true});

  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
        fontStyle: italic ? FontStyle.italic : null,
        color: StateChip.colorsFor(context, Severity.neutral).$2,
      ));
}

/// An activity cell before its value is known: loading, failed, or blank
/// on a server without listUserActivity. Null once the value is there.
Widget? _pendingCell(_ActivityState state, Object? error) => switch (state) {
      _ActivityState.loading => const Tooltip(
          message: 'Loading activity',
          child: _Muted('…', key: Key('activity-loading'), italic: false)),
      _ActivityState.failed => Tooltip(
          message: 'Activity could not be loaded: $error',
          child: const Icon(Icons.error_outline,
              key: Key('activity-error'), size: 16)),
      _ActivityState.unavailable => const SizedBox.shrink(),
      _ActivityState.loaded => null,
    };

/// An active-days count: the number; "≥N" when the server stopped reading
/// before the user's oldest activity, so N is a lower bound; "unknown" —
/// muted and italic, never a number — when the server could not count.
class _ActiveDays extends StatelessWidget {
  final int? days;
  final bool lowerBound;
  const _ActiveDays(this.days, {required this.lowerBound});

  @override
  Widget build(BuildContext context) {
    final days = this.days;
    if (days == null) {
      return const Tooltip(
        message: "The server could not read this user's activity",
        child: _Muted('unknown', key: Key('active-days-unknown')),
      );
    }
    if (!lowerBound) return Text('$days');
    return Tooltip(
      message: 'At least $days: the server stopped reading at its budget, '
          'before the oldest activity',
      child: Text('≥$days'),
    );
  }
}

/// One object in the Last worked on cell: a kind icon and its name, a link
/// to it in Tercen when its project's owner is known. A deleted object is
/// struck through and marked, and not linked: the link would lead nowhere.
class _ActivityEntry extends StatelessWidget {
  static const maxWidth = 200.0;
  final ActivityObject entry;
  final DashboardData data;
  const _ActivityEntry(this.entry, this.data);

  /// The object's page: a workflow's own, anything else its project's.
  /// None without an owner.
  static String? url(DashboardData data, ActivityObject e) {
    final owner = e.owner;
    if (owner == null) return null;
    if (e.kind == 'Workflow') return data.workflowUrl(owner, e.id);
    final projectId = e.projectId.isNotEmpty
        ? e.projectId
        : (e.kind == 'Project' ? e.id : '');
    return projectId.isEmpty ? null : data.projectUrl(owner, projectId);
  }

  @override
  Widget build(BuildContext context) {
    final muted = StateChip.colorsFor(context, Severity.neutral).$2;
    final label = entry.name.isNotEmpty ? entry.name : entry.kind;
    final link = entry.isDeleted ? null : url(data, entry);
    final Widget text;
    if (entry.isDeleted) {
      text = Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: muted, decoration: TextDecoration.lineThrough)),
        ),
        const SizedBox(width: 4),
        Text('deleted',
            key: const Key('activity-deleted'),
            style: TextStyle(
                color: muted, fontSize: 11, fontStyle: FontStyle.italic)),
      ]);
    } else if (link == null) {
      text = Text(label, maxLines: 1, overflow: TextOverflow.ellipsis);
    } else {
      text = LinkText(text: label, url: link);
    }
    final where = entry.projectName.isEmpty ? '' : ' · ${entry.projectName}';
    return Tooltip(
      message: '${entry.kind} · ${entry.type} ${formatDate(entry.date)}$where',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
              switch (entry.kind) {
                'Workflow' => Icons.account_tree_outlined,
                'Project' => Icons.folder_outlined,
                _ => Icons.description_outlined,
              },
              size: 14,
              color: muted),
          const SizedBox(width: 4),
          Flexible(child: text),
        ]),
      ),
    );
  }
}

/// The Last worked on cell: the latest object and a "+N" toggle; open,
/// every object the server sent (at most ten), newest first, in the row.
class _RecentCell extends StatelessWidget {
  final List<ActivityObject>? recent;
  final DashboardData data;
  final bool expanded;
  final VoidCallback onToggle;
  const _RecentCell({
    required this.recent,
    required this.data,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final recent = this.recent;
    if (recent == null) {
      return const Tooltip(
        message: "The server could not read this user's activity",
        child: _Muted('unknown', key: Key('recent-unknown')),
      );
    }
    if (recent.isEmpty) return const _Muted('none', key: Key('recent-none'));
    final more = recent.length - 1;
    final toggle = more == 0
        ? null
        : InkWell(
            key: const Key('activity-toggle'),
            onTap: onToggle,
            child: Tooltip(
              message: expanded
                  ? 'Show only the latest'
                  : 'Show the last ${recent.length}',
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16),
                if (!expanded)
                  Text('+$more', style: const TextStyle(fontSize: 11.5)),
              ]),
            ),
          );
    if (!expanded) {
      return Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
        _ActivityEntry(recent.first, data),
        ?toggle,
      ]);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          Column(
            key: const Key('activity-expanded'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [for (final e in recent) _ActivityEntry(e, data)],
          ),
          ?toggle,
        ],
      ),
    );
  }
}

/// The line under the count while the activity columns are not filled:
/// loading, failed (with a retry), or not provided by this server.
class _ActivityStatus extends StatelessWidget {
  final _ActivityState state;
  final Object? error;
  final VoidCallback retry;
  const _ActivityStatus(this.state, this.error, this.retry);

  @override
  Widget build(BuildContext context) {
    final (Widget icon, String text) = switch (state) {
      _ActivityState.loading => (
          const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2)),
          'Loading activity — the table can be used meanwhile',
        ),
      _ActivityState.failed => (
          const Icon(Icons.error_outline, size: 16),
          'Activity could not be loaded: $error',
        ),
      _ActivityState.unavailable => (
          const Icon(Icons.info_outline, size: 16),
          'This server does not report user activity; those columns are '
              'blank',
        ),
      _ActivityState.loaded => (const SizedBox.shrink(), ''),
    };
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [
        icon,
        const SizedBox(width: 6),
        Flexible(
          child: Text(text,
              key: const Key('activity-status'),
              style: Theme.of(context).textTheme.bodySmall),
        ),
        if (state == _ActivityState.failed)
          TextButton(onPressed: retry, child: const Text('Retry')),
      ]),
    );
  }
}

/// The users the filters leave, and how many they left out: [excluded]
/// by email domain, and with [byActivity] (MAU, activity loaded) the
/// [unknown] ones whose activity in the window could not be counted.
class _Counted {
  final List<DashboardUser> users;
  final int excluded;
  final int unknown;
  final bool byActivity;
  const _Counted(this.users,
      {required this.excluded, this.unknown = 0, this.byActivity = false});
}

/// Material draws no scrollbar on a horizontal scroll view, so a table wider
/// than the card would hide its last columns without a sign. This one shows
/// the horizontal thumb whenever there is something to scroll to: under the
/// rows, and under the pager if the pager is ever wider than the card.
class _HorizontalScrollbar extends MaterialScrollBehavior {
  const _HorizontalScrollbar();

  @override
  Widget buildScrollbar(
      BuildContext context, Widget child, ScrollableDetails details) {
    if (axisDirectionToAxis(details.direction) != Axis.horizontal) {
      return super.buildScrollbar(context, child, details);
    }
    return Scrollbar(
      controller: details.controller,
      thumbVisibility: true,
      child: child,
    );
  }
}

class _UsersScreenState extends State<UsersScreen> {
  final _filterField = TextEditingController();
  String _filter = '';

  /// A user just created, to bring on screen once the reload lists them;
  /// then the one whose row carries [_revealKey].
  String? _reveal;
  String? _revealedName;

  /// The page to open the table at, and a count that rebuilds the table
  /// there: it goes up each time a created user is brought on screen.
  int _firstRow = 0;
  int _revealed = 0;
  final _revealKey = GlobalKey();

  static const _pageSizes = [25, 50, 100];
  int _rowsPerPage = 50;

  /// Grantable roles (the server enforces the same list). `user` is the
  /// baseline every account carries and is not offered here.
  static const _roles = ['manager', 'operator', 'admin'];

  /// The filter bar's settings, and the window last asked for: all time
  /// shows no Days in window column; a new window reloads the activity.
  late UserFilters _filters = UserFilters.load(widget.data.settings);
  ActivityWindow _window = const ActivityWindow.allTime();
  final _excludeField = TextEditingController();

  /// Goes up with each filter change: the table starts again at page one.
  int _filterChanges = 0;

  /// The activity columns: loaded once per window, beside the list.
  _ActivityState _activityState = _ActivityState.loading;
  UserActivityReport? _activity;
  Object? _activityError;
  int _activityRequest = 0;

  /// Users whose Last worked on cell is open, by domain and id.
  final _expanded = <(String, String)>{};

  @override
  void initState() {
    super.initState();
    _loadActivity();
  }

  @override
  void dispose() {
    _filterField.dispose();
    _excludeField.dispose();
    super.dispose();
  }

  /// Keeps [filters], and reloads the activity when they name a window
  /// other than the one last asked for — which, for MAU, is also the case
  /// once the UTC day has moved on since.
  void _setFilters(UserFilters filters) {
    final reload = filters.window(widget.data.now()) != _window;
    setState(() {
      _filters = filters;
      _filterChanges++;
    });
    filters.save(widget.data.settings);
    if (reload) _loadActivity();
  }

  /// Asks for the activity over the filters' window and fills the columns
  /// when it comes. An answer to an older request (the window changed
  /// meanwhile) is dropped.
  Future<void> _loadActivity() async {
    final request = ++_activityRequest;
    final window = _filters.window(widget.data.now());
    if (mounted) {
      setState(() {
        _window = window;
        _activityState = _ActivityState.loading;
        _activityError = null;
      });
    }
    try {
      final report = await widget.data.userActivity(window: window);
      if (!mounted || request != _activityRequest) return;
      setState(() {
        _activity = report;
        _activityState = report == null
            ? _ActivityState.unavailable
            : _ActivityState.loaded;
      });
    } catch (e) {
      if (!mounted || request != _activityRequest) return;
      setState(() {
        _activityError = e;
        _activityState = _ActivityState.failed;
      });
    }
  }

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

  /// Opens the Create user dialog; after a create, clears the filter and
  /// reloads the list, and the table then opens at the page that holds the
  /// new user.
  Future<void> _createUser(BuildContext context, VoidCallback refresh) async {
    final created = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CreateUserDialog(create: widget.data.createUser),
    );
    if (created == null) return;
    _filterField.clear();
    setState(() {
      _filter = '';
      _reveal = created;
    });
    refresh();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Created $created'), width: 320));
    }
  }

  /// Whether this admin may edit [user]'s tags from here: only on a row of
  /// the admin's own domain. The user endpoints find a document by id in
  /// the session's domain, and the default accounts have the same id in
  /// every domain, so an edit from another domain's row would load and save
  /// the admin's own domain's user of that id, not the one the row shows.
  bool _canEditTags(DashboardUser user) =>
      widget.data.session.isAdmin && user.domain == widget.data.session.domain;

  /// Opens the tag editor on [user]'s stored document; after a save,
  /// reloads the list.
  Future<void> _editTags(
      BuildContext context, DashboardUser user, VoidCallback refresh) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EditTagsDialog(
        userName: user.name,
        load: () => widget.data.userDocument(user.id),
        save: widget.data.saveUserDocument,
      ),
    );
    if (saved != true) return;
    refresh();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved the tags of ${user.name}'), width: 320));
    }
  }

  DataRow _userRow(
      BuildContext context, DashboardUser user, VoidCallback refresh) {
    return DataRow(cells: [
      DataCell(Text(user.name,
          key: user.name == _revealedName ? _revealKey : null)),
      DataCell(Text(user.email)),
      // A Row, not a Wrap: a Wrap in a Row leaves its gaps out of the
      // column's width, and three roles overflowed the cell.
      DataCell(Row(spacing: 4, children: [
        for (final role in user.roles)
          if (role != 'user') StateChip(role),
        _RoleMenu(
          roles: user.roles,
          onChange: (role, grant) =>
              _changeRole(context, user, role, grant, refresh),
        ),
      ])),
      DataCell(Icon(
        user.isValidated ? Icons.check_circle_outline : Icons.hourglass_empty,
        size: 18,
        color: user.isValidated
            ? StateChip.colorsFor(context, Severity.ok).$2
            : StateChip.colorsFor(context, Severity.neutral).$2,
      )),
      DataCell(Text(user.domain.isEmpty ? 'default' : user.domain)),
      DataCell(Text(formatDate(user.createdDate))),
      ..._activityCells(user),
      DataCell(_ProjectsOwned(user)),
      DataCell(Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
        _Tags(user.tags ?? const []),
        if (_canEditTags(user))
          IconButton(
            key: Key('edit-tags-${user.domain}-${user.id}'),
            tooltip: 'Edit tags',
            icon: const Icon(Icons.edit_outlined, size: 15),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => _editTags(context, user, refresh),
          ),
      ])),
    ]);
  }

  /// A window, on a server that counts one.
  bool get _windowed =>
      !_window.isAllTime && _activityState != _ActivityState.unavailable;

  /// Last worked on, Active days and — with a window — Days in window.
  List<DataCell> _activityCells(DashboardUser user) {
    final count = _windowed ? 3 : 2;
    final pending = _pendingCell(_activityState, _activityError);
    if (pending != null) return List.filled(count, DataCell(pending));
    final key = (user.domain, user.id);
    final activity = _activity?[key];
    // A user the answer does not name (created since it was read): blank.
    if (activity == null) {
      return List.filled(count, const DataCell(SizedBox.shrink()));
    }
    return [
      DataCell(_RecentCell(
        recent: activity.recent,
        data: widget.data,
        expanded: _expanded.contains(key),
        onToggle: () => setState(() {
          if (!_expanded.remove(key)) _expanded.add(key);
        }),
      )),
      DataCell(
          _ActiveDays(activity.activeDays, lowerBound: activity.truncated)),
      if (_windowed)
        DataCell(_ActiveDays(activity.activeDaysInWindow,
            lowerBound: activity.windowTruncated)),
    ];
  }

  /// The users the filters leave: none of the excluded email domains, and
  /// under MAU, once the activity is in, only those active in the window.
  _Counted _count(UserListing listing) {
    final kept = [
      for (final u in listing.users)
        if (!_filters.excludes(u)) u,
    ];
    final excluded = listing.users.length - kept.length;
    if (!_filters.isMau || _activityState != _ActivityState.loaded) {
      return _Counted(kept, excluded: excluded);
    }
    final active = <DashboardUser>[];
    var unknown = 0;
    for (final u in kept) {
      switch (windowActivity(_activity?[(u.domain, u.id)])) {
        case WindowActivity.active:
          active.add(u);
        case WindowActivity.unknown:
          unknown++;
        case WindowActivity.inactive:
          break;
      }
    }
    return _Counted(active,
        excluded: excluded, unknown: unknown, byActivity: true);
  }

  /// The line under the count in MAU mode: the window, and what the MAU
  /// cannot say — users whose activity could not be counted are neither
  /// active nor inactive, so they make the MAU a range, and a list the
  /// server cut short counts only the users it returned.
  String? _mauNote(UserListing listing, _Counted counted) {
    if (!_filters.isMau) return null;
    final window = '$_window (UTC)';
    switch (_activityState) {
      case _ActivityState.loading:
        return 'MAU, $window: waiting for the activity — until it comes '
            'the list is not narrowed to active users';
      case _ActivityState.failed:
        return 'MAU unavailable: the activity could not be loaded, so the '
            'list is not narrowed to active users';
      case _ActivityState.unavailable:
        return 'MAU unavailable: this server does not report user activity';
      case _ActivityState.loaded:
        final active = counted.users.length;
        final unknown = counted.unknown;
        final range = unknown == 0
            ? '$active'
            : '$active to ${active + unknown}: $unknown more '
                '${unknown == 1 ? 'user' : 'users'} whose activity in the '
                'window could not be counted ${unknown == 1 ? 'is' : 'are'} '
                'not shown';
        final part = listing.mayHaveMore
            ? ' — of the users loaded; the server returned only part of '
                'the list'
            : '';
        return 'MAU, $window: users active in the window — $range$part';
    }
  }

  Future<void> _chooseWindow(BuildContext context) async {
    final utc = widget.data.now().toUtc();
    final today = DateTime(utc.year, utc.month, utc.day);
    DateTime? day(String s) {
      final d = DateTime.tryParse(s);
      return d == null ? null : DateTime(d.year, d.month, d.day);
    }

    final current = _filters.mode == WindowMode.allTime
        ? null
        : (day(_window.from), day(_window.to));
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2015),
      lastDate: today,
      currentDate: today,
      initialDateRange: current == null ||
              current.$1 == null ||
              current.$2 == null ||
              current.$2!.isAfter(today)
          ? null
          : DateTimeRange(start: current.$1!, end: current.$2!),
      helpText: 'Activity window, UTC days, both included',
    );
    if (picked == null) return;
    _setFilters(_filters.copyWith(
        mode: WindowMode.custom,
        from: formatDay(picked.start),
        to: formatDay(picked.end)));
  }

  void _addExclusion(String typed) {
    final domain = normalizeDomain(typed);
    _excludeField.clear();
    if (domain.isEmpty || _filters.excluded.contains(domain)) return;
    _setFilters(_filters.copyWith(excluded: [..._filters.excluded, domain]));
  }

  /// Activity: all time, a chosen window, or MAU; then the excluded email
  /// domains. The window choices are off on a server without activity.
  Widget _filterBar(BuildContext context) {
    final theme = Theme.of(context);
    final noActivity = _activityState == _ActivityState.unavailable;
    const offTip = 'This server does not report user activity';
    Widget choice(Key key, String label, bool selected, String tip,
            VoidCallback onTap) =>
        Tooltip(
          message: noActivity ? offTip : tip,
          child: ChoiceChip(
            key: key,
            label: Text(label),
            selected: selected,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            onSelected: noActivity ? null : (_) => onTap(),
          ),
        );
    final mode = _filters.mode;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Activity', style: theme.textTheme.labelSmall),
        choice(
            const Key('filter-all-time'),
            'All time',
            mode == WindowMode.allTime,
            'Active days over all time; no window',
            () => _setFilters(_filters.copyWith(mode: WindowMode.allTime))),
        choice(
            const Key('filter-window'),
            mode == WindowMode.custom
                ? '${_filters.from} – ${_filters.to}'
                : 'Choose dates…',
            mode == WindowMode.custom,
            'Count active days between two UTC days, both included',
            () => _chooseWindow(context)),
        choice(
            const Key('filter-mau'),
            'MAU · last ${UserFilters.mauDays} days',
            mode == WindowMode.mau,
            'Only users active in the last ${UserFilters.mauDays} days '
                '(UTC, today included); the count is the MAU',
            () => _setFilters(_filters.copyWith(mode: WindowMode.mau))),
        const SizedBox(width: 12),
        Text('Exclude', style: theme.textTheme.labelSmall),
        for (final domain in _filters.excluded)
          InputChip(
            key: Key('excluded-$domain'),
            label: Text('@$domain'),
            visualDensity: VisualDensity.compact,
            deleteButtonTooltipMessage: 'Include @$domain again',
            onDeleted: () => _setFilters(_filters.copyWith(excluded: [
              for (final d in _filters.excluded)
                if (d != domain) d,
            ])),
          ),
        SizedBox(
          width: 200,
          child: TextField(
            key: const Key('filter-exclude'),
            controller: _excludeField,
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Email domain, e.g. example.test',
              border: OutlineInputBorder(),
            ),
            onSubmitted: _addExclusion,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshingPanel<UserListing>(
      title: 'Users',
      interval: const Duration(minutes: 2),
      load: widget.data.users,
      actions: [
        SizedBox(
          width: 240,
          child: TextField(
            key: const Key('users-search'),
            controller: _filterField,
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Filter by name or email',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() {
              _filter = value.toLowerCase();
              _firstRow = 0;
            }),
          ),
        ),
        const SizedBox(width: 8),
      ],
      builder: (context, listing, refresh) {
        final counted = _count(listing);
        final visible = counted.users
            .where((u) =>
                _filter.isEmpty ||
                u.name.toLowerCase().contains(_filter) ||
                u.email.toLowerCase().contains(_filter) ||
                u.domain.toLowerCase().contains(_filter))
            .toList();
        final theme = Theme.of(context);
        // A created user the filters hide is not waited for.
        if (_reveal != null &&
            !visible.any((u) => u.name == _reveal) &&
            listing.users.any((u) => u.name == _reveal)) {
          _reveal = null;
        }
        final mauNote = _mauNote(listing, counted);
        // The filter bar, the count line, and for admins the Create user
        // button beside it.
        final banner = Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _filterBar(context),
                const SizedBox(height: 8),
                Text(
                    showingBanner(listing, visible.length,
                        excluded: counted.excluded),
                    key: const Key('users-banner'),
                    style: theme.textTheme.bodySmall),
                if (mauNote != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(mauNote,
                        key: const Key('mau-note'),
                        style: theme.textTheme.bodySmall),
                  ),
                _ActivityStatus(_activityState, _activityError, _loadActivity),
              ],
            ),
          ),
          if (widget.data.session.isAdmin)
            FilledButton.icon(
              onPressed: () => _createUser(context, refresh),
              icon: const Icon(Icons.person_add_alt_outlined, size: 18),
              label: const Text('Create user'),
            ),
        ]);
        if (visible.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              banner,
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Text(
                      listing.viaFallback
                          ? 'This server has no AdminService, so the list came '
                              'from findUserByCreatedDateAndName — a view that '
                              'returns nothing on some instances (the built-in '
                              'admin console is empty here too). Upgrade the '
                              'server for a reliable listing.'
                          : 'No matching users.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        final onePage = visible.length < _pageSizes.first;
        // Once the reload lists the created user, open the table at their
        // page and scroll their row into view.
        final at = _reveal == null
            ? -1
            : visible.indexWhere((u) => u.name == _reveal);
        if (at >= 0) {
          _firstRow = onePage ? 0 : at - at % _rowsPerPage;
          _revealed++;
          _revealedName = _reveal;
          _reveal = null;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final row = _revealKey.currentContext;
            if (row != null && row.mounted) Scrollable.ensureVisible(row);
          });
        }
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              banner,
              const SizedBox(height: 8),
              Theme(
                data: theme.copyWith(
                  dataTableTheme: theme.dataTableTheme.copyWith(
                    headingTextStyle: theme.textTheme.labelSmall
                        ?.copyWith(letterSpacing: 0.6),
                    // A row grows to hold an open Last worked on cell; the
                    // others keep their height. Set on the theme, not the
                    // table: the table multiplies its own value into the
                    // space below a short last page, and infinity there is
                    // NaN. A finite value would stretch every row to it.
                    dataRowMaxHeight: double.infinity,
                  ),
                ),
                child: ScrollConfiguration(
                  behavior: const _HorizontalScrollbar(),
                  child: PaginatedDataTable(
                    // A new filter starts again at the first page, and so
                    // does the MAU list once the activity filters it; a
                    // created user opens it at theirs.
                    key: ValueKey(
                        (_filter, _filterChanges, counted.byActivity, _revealed)),
                    initialFirstRowIndex: _firstRow,
                    // The table keeps a full page of height below the last
                    // row, so a list that fits on one page gets a page of its
                    // own size: the pager then sits under the rows, not a
                    // screen below them.
                    rowsPerPage: onePage ? visible.length : _rowsPerPage,
                    availableRowsPerPage: _pageSizes,
                    onRowsPerPageChanged: onePage
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _rowsPerPage = value);
                            }
                          },
                    showEmptyRows: false,
                    showFirstLastButtons: true,
                    // Ten columns or more: at the default spacing the last
                    // ones fall off a laptop-width screen.
                    columnSpacing: 20,
                    columns: [
                      const DataColumn(label: Text('NAME')),
                      const DataColumn(label: Text('EMAIL')),
                      const DataColumn(label: Text('ROLES')),
                      const DataColumn(label: Text('VALIDATED')),
                      const DataColumn(label: Text('DOMAIN')),
                      const DataColumn(label: Text('CREATED')),
                      const DataColumn(
                          label: Text('LAST\nWORKED ON'),
                          tooltip: 'The last workflows and other objects '
                              'worked on, newest first'),
                      const DataColumn(
                          label: Text('ACTIVE\nDAYS', textAlign: TextAlign.end),
                          tooltip: 'Days with activity, all time',
                          numeric: true),
                      if (_windowed)
                        DataColumn(
                            label: const Text('DAYS IN\nWINDOW',
                                textAlign: TextAlign.end),
                            tooltip: 'Days with activity, $_window (UTC)',
                            numeric: true),
                      // On two lines: on one, the heading is three times
                      // as wide as a four-digit count.
                      const DataColumn(
                          label: Text('PROJECTS\nOWNED',
                              textAlign: TextAlign.end),
                          numeric: true),
                      const DataColumn(label: Text('TAGS')),
                    ],
                    source: _UserRows(
                        visible, (user) => _userRow(context, user, refresh)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
