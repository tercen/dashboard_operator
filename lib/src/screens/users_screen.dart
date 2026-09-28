import 'package:flutter/material.dart';

import '../data.dart';
import '../widgets.dart';
import 'create_user_dialog.dart';

/// The count line above the table. [shown] is the number of rows left after
/// the filter. The total is the server's when it reports one; otherwise it
/// is the number of users loaded, and the line says the total is unknown.
/// It claims only what the response supports: a server that says the list is
/// truncated but gives no total has not said why, so the line does not blame
/// the limit.
String showingBanner(UserListing listing, int shown) {
  final loaded = listing.users.length;
  final total = listing.total;
  if (total != null) {
    return listing.mayHaveMore
        ? 'Showing $shown of $total users — the server returned only the '
            'first $loaded'
        : 'Showing $shown of $total users';
  }
  if (listing.truncated == true) {
    return 'Showing $shown of the first $loaded users — the server reported '
        'the list as incomplete; it does not report a total';
  }
  return listing.mayHaveMore
      ? 'Showing $shown of the first $loaded users — the list stopped at the '
          'limit of ${listing.limit}; this server does not report a total'
      : 'Showing $shown of $loaded users loaded; this server does not '
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

  @override
  void dispose() {
    _filterField.dispose();
    super.dispose();
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
      DataCell(_ProjectsOwned(user)),
      DataCell(_Tags(user.tags ?? const [])),
    ]);
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
        final visible = listing.users
            .where((u) =>
                _filter.isEmpty ||
                u.name.toLowerCase().contains(_filter) ||
                u.email.toLowerCase().contains(_filter) ||
                u.domain.toLowerCase().contains(_filter))
            .toList();
        final theme = Theme.of(context);
        // The count line, and for admins the Create user button beside it.
        final banner = Row(children: [
          Expanded(
            child: Text(showingBanner(listing, visible.length),
                key: const Key('users-banner'),
                style: theme.textTheme.bodySmall),
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
                  ),
                ),
                child: ScrollConfiguration(
                  behavior: const _HorizontalScrollbar(),
                  child: PaginatedDataTable(
                    // A new filter starts again at the first page; a created
                    // user opens it at theirs.
                    key: ValueKey((_filter, _revealed)),
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
                    // Eight columns: at the default spacing the last ones fall
                    // off a laptop-width screen.
                    columnSpacing: 20,
                    columns: const [
                      DataColumn(label: Text('NAME')),
                      DataColumn(label: Text('EMAIL')),
                      DataColumn(label: Text('ROLES')),
                      DataColumn(label: Text('VALIDATED')),
                      DataColumn(label: Text('DOMAIN')),
                      DataColumn(label: Text('CREATED')),
                      // On two lines: on one, the heading is three times
                      // as wide as a four-digit count.
                      DataColumn(
                          label: Text('PROJECTS\nOWNED',
                              textAlign: TextAlign.end),
                          numeric: true),
                      DataColumn(label: Text('TAGS')),
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
