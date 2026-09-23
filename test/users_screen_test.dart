import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sci_http_client/content_codec.dart';
import 'package:sci_http_client/http_client.dart' as http_api;

import 'package:tercen_dashboard/src/admin_api.dart';
import 'package:tercen_dashboard/src/data.dart';
import 'package:tercen_dashboard/src/screens/users_screen.dart';
import 'package:tercen_dashboard/src/screens/tasks_screen.dart';
import 'package:tercen_dashboard/src/theme.dart';
import 'package:tercen_dashboard/src/user_activity.dart';
import 'package:tercen_dashboard/src/user_filters.dart';

import 'support/fake_data.dart';

class _FakeResponse implements http_api.Response {
  @override
  final int statusCode;
  @override
  final Map? headers = const {};
  @override
  final Object? body;
  _FakeResponse(this.body, {this.statusCode = 200});
}

/// Answers listUsers with [report], and grantRole/revokeRole as a server
/// would: the change is recorded in [report]'s rows, so the next listUsers
/// shows it, and the call answers with the user's new roles.
///
/// listUserActivity answers with [activity] once [activityGate] (if any)
/// completes, fails with [activityStatus] when that is not 200, and is a
/// 404 — a server before tercen/sci#1667 — when [activity] is null.
/// With [holdActivity], each listUserActivity call is instead held in
/// [held] until the test answers that one call ([answerHeld], [failHeld]).
class _ReportClient implements http_api.HttpClient {
  final Map<String, Object?> report;
  final List<String> calls = [];
  Map<String, Object?>? activity;
  int activityStatus = 200;
  Future<void>? activityGate;
  bool holdActivity = false;
  final List<Completer<http_api.Response>> held = [];
  final List<Map<String, Object?>> activityParams = [];
  _ReportClient(this.report);

  /// Answers held call [i] with [activity].
  void answerHeld(int i, Map<String, Object?> activity) => held[i].complete(
      _FakeResponse(ContentCodec.tson().encode([json.encode(activity)])));

  /// Fails held call [i] as a server error would.
  void failHeld(int i) => held[i].complete(_FakeResponse(
      ContentCodec.tson().encode({'error': 'admin.invented', 'reason': 'invented'}),
      statusCode: 500));

  @override
  Future<http_api.Response> post(url,
      {Map<String, String>? headers,
      body,
      String? responseType,
      encoding,
      progressCallback}) async {
    final codec = ContentCodec.tson();
    final endpoint = Uri.parse('$url').pathSegments.last;
    if (endpoint == 'grantRole' || endpoint == 'revokeRole') {
      final params = Map<String, Object?>.from(codec.decode(body) as Map);
      final row = (report['rows'] as List)
          .cast<Map<String, Object?>>()
          .firstWhere((r) => r['name'] == params['username']);
      final roles = [...(row['roles'] as List).cast<String>()];
      endpoint == 'grantRole'
          ? roles.add('${params['role']}')
          : roles.remove(params['role']);
      row['roles'] = roles;
      calls.add('$endpoint ${params['username']} ${params['role']}');
      return _FakeResponse(codec.encode(roles));
    }
    if (endpoint == 'listUserActivity') {
      activityParams.add(Map<String, Object?>.from(codec.decode(body) as Map));
      if (holdActivity) {
        final call = Completer<http_api.Response>();
        held.add(call);
        return call.future;
      }
      await activityGate;
      final activity = this.activity;
      if (activity == null) return _FakeResponse('', statusCode: 404);
      if (activityStatus != 200) {
        return _FakeResponse(
            codec.encode({'error': 'admin.invented', 'reason': 'invented'}),
            statusCode: activityStatus);
      }
      return _FakeResponse(codec.encode([json.encode(activity)]));
    }
    calls.add(endpoint);
    return _FakeResponse(codec.encode(json.encode(report)));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// The real [DashboardData.users] and [DashboardData.changeRole], over a
/// server that answers [report], with the filters kept in [settings] and
/// the clock at [clock]: 15 October 2026, 12:00 UTC, unless a test says.
class _ReportData extends DashboardData {
  final _ReportClient client;
  DateTime clock;
  _ReportData(Map<String, Object?> report,
      {MemorySettings? settings, DateTime? clock})
      : client = _ReportClient(report),
        clock = clock ?? DateTime.utc(2026, 10, 15, 12),
        super(
            fakeAdminSession()
              ..serviceBase = Uri.parse('https://tercen.example'),
            settings: settings ?? MemorySettings());

  @override
  DateTime now() => clock;

  @override
  AdminApi get adminApi => AdminApi(Uri.parse('https://tercen.example'), client);
}

/// [count] invented users, newest first; `user-007` has no createdDate.
List<Map<String, Object?>> _rows(int count) => [
      for (var i = 1; i <= count; i++)
        {
          'id': 'id-$i',
          'name': 'user-${i.toString().padLeft(3, '0')}',
          'email': 'user$i@example.test',
          'domain': i.isEven ? 'north' : '',
          'roles': i == 1 ? ['user', 'admin'] : ['user'],
          'isValidated': i != 2,
          'createdDate': i == 7 ? null : '2026-09-01T12:00:00',
        }
    ];

/// The Users page over a server that answers [report], and [activity]
/// for listUserActivity (none: the route is missing). With a [gate] the
/// activity waits for it, and with [hold] each call waits for the test to
/// answer it; either way the page is pumped, not settled: its loading
/// spinner never settles.
Future<_ReportData> _pump(
  WidgetTester tester,
  Map<String, Object?> report, {
  Map<String, Object?>? activity,
  int activityStatus = 200,
  Future<void>? gate,
  bool hold = false,
  UserFilters filters = const UserFilters(),
  MemorySettings? settings,
  DateTime? clock,
}) async {
  final data = _ReportData(report, settings: settings, clock: clock);
  if (settings == null) filters.save(data.settings);
  data.client
    ..activity = activity
    ..activityStatus = activityStatus
    ..activityGate = gate
    ..holdActivity = hold;
  tester.view
    ..physicalSize = const Size(1280, 1600)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(data));
  if (gate == null && !hold) {
    await tester.pumpAndSettle();
  } else {
    await _pumpFrames(tester);
  }
  return data;
}

/// A few frames, for a page whose loading spinner never settles.
Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Widget _app(DashboardData data) => MaterialApp(
      theme: DashboardTheme.light,
      home: Scaffold(body: UsersScreen(data: data)),
    );

/// Sets the activity window with the filter bar's date picker, typing the
/// days as an admin would. [from] and [to] are YYYY-MM-DD; the picker
/// takes them as MM/DD/YYYY in the test's locale. Pumps, and settles
/// unless the activity is held.
Future<void> _chooseWindow(WidgetTester tester, String from, String to,
    {bool settle = true}) async {
  String typed(String day) {
    final [y, m, d] = day.split('-');
    return '$m/$d/$y';
  }

  Future<void> pump() => settle ? tester.pumpAndSettle() : _pumpFrames(tester);
  await tester.tap(find.byKey(const Key('filter-window')));
  await pump();
  await tester.tap(find.byTooltip('Switch to input'));
  await pump();
  final fields = find.descendant(
      of: find.byType(Dialog), matching: find.byType(TextField));
  await tester.enterText(fields.at(0), typed(from));
  await tester.enterText(fields.at(1), typed(to));
  await tester.tap(find.text('OK'));
  await pump();
}

/// The panel refreshes on a timer; unmount so it does not outlive the test.
Future<void> _unmount(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox());

/// The pager sits below the rows: scroll to it, as a user would.
Future<void> _nextPage(WidgetTester tester) async {
  await tester.ensureVisible(find.byTooltip('Next page'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Next page'));
}

/// The texts on [name]'s row, left to right: every Text in the table level
/// with the name. Icons (Validated, the role menu) are not Texts.
List<String> _rowTexts(WidgetTester tester, String name) {
  final y = tester.getCenter(find.text(name)).dy;
  final texts = find.descendant(
      of: find.byType(DataTable), matching: find.byType(Text));
  final onRow = [
    for (var i = 0; i < texts.evaluate().length; i++)
      if ((tester.getCenter(texts.at(i)).dy - y).abs() < 4) texts.at(i),
  ]..sort((a, b) =>
      tester.getCenter(a).dx.compareTo(tester.getCenter(b).dx));
  return [for (final t in onRow) tester.widget<Text>(t).data!];
}

/// Rows as a server with tercen/sci#1664 sends them: `tags` and
/// `projectsOwned` on every row, a null count where the server could not
/// count, 0 where it counted none.
List<Map<String, Object?>> _w3Rows() => [
      for (final (name, domain, tags, owned) in [
        ('user-a', '', ['pilot', 'beta'], 4),
        ('user-b', 'north', <String>[], 0),
        ('user-c', 'north', ['beta'], null),
      ])
        {
          'id': 'id-$name',
          'name': name,
          'email': '$name@example.test',
          'domain': domain,
          'roles': ['user'],
          'isValidated': true,
          'createdDate': '2026-09-01T12:00:00',
          'tags': tags,
          'projectsOwned': owned,
        }
    ];

/// [_w3Rows] as a server with tercen/sci#1663 reports them.
Map<String, Object?> _w3Report() =>
    {'rows': _w3Rows(), 'total': 3, 'truncated': false};

/// listUserActivity's answer for [_w3Rows], invented, in tercen/sci#1667's
/// shape. user-a has ten objects: a workflow and a project on others'
/// projects, a deleted workflow, a file whose project is gone (owner
/// null), and six more workflows. user-b was read and has none; the server
/// could not read user-c (nulls). With a [window], user-a has 7 days in it.
Map<String, Object?> _activity({(String, String)? window}) {
  Map<String, Object?> object(String kind, String id, String name,
          {String type = 'update',
          String projectId = 'pr-1',
          String? owner = 'team-x'}) =>
      {
        'kind': kind,
        'id': id,
        'name': name,
        'type': type,
        'date': '2026-09-20T10:00:00.000Z',
        'projectId': projectId,
        'projectName': 'Invented project',
        'owner': owner,
      };
  return {
    'budget': 20000,
    'dayBoundary': 'UTC',
    'window': window == null ? null : {'from': window.$1, 'to': window.$2},
    'truncatedUsers': 0,
    'rows': [
      {
        'id': 'id-user-a',
        'name': 'user-a',
        'domain': '',
        'activeDays': 40,
        'activeDaysInWindow': window == null ? null : 7,
        'recent': [
          object('Workflow', 'wf-a1', 'Gating'),
          object('Project', 'pr-2', 'Pilot', projectId: 'pr-2', owner: 'user-a'),
          object('Workflow', 'wf-a3', 'Old flow', type: 'delete'),
          object('FileDocument', 'fd-1', 'plate.csv',
              projectId: 'pr-9', owner: null),
          for (var i = 5; i <= 10; i++) object('Workflow', 'wf-a$i', 'Flow $i'),
        ],
        'scanned': 120,
        'oldestScanned': '2025-01-01T00:00:00.000Z',
        'truncated': false,
        'windowTruncated': window == null ? null : false,
      },
      {
        'id': 'id-user-b',
        'name': 'user-b',
        'domain': 'north',
        'activeDays': 0,
        'activeDaysInWindow': window == null ? null : 0,
        'recent': <Object>[],
        'scanned': 0,
        'oldestScanned': null,
        'truncated': false,
        'windowTruncated': window == null ? null : false,
      },
      {
        'id': 'id-user-c',
        'name': 'user-c',
        'domain': 'north',
        'activeDays': null,
        'activeDaysInWindow': null,
        'recent': null,
        'scanned': null,
        'oldestScanned': null,
        'truncated': null,
        'windowTruncated': null,
      },
    ],
  };
}

String _status(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('activity-status'))).data!;

String _banner(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('users-banner'))).data!;

void main() {
  group('new response shape (rows, total, truncated)', () {
    testWidgets('pages the rows and counts against the server total',
        (tester) async {
      await _pump(tester,
          {'rows': _rows(120), 'total': 120, 'truncated': false});

      expect(find.byType(PaginatedDataTable), findsOneWidget);
      expect(_banner(tester), 'Showing 120 of 120 users');
      for (final column in [
        'NAME',
        'EMAIL',
        'ROLES',
        'VALIDATED',
        'DOMAIN',
        'CREATED',
        'PROJECTS\nOWNED',
        'TAGS',
      ]) {
        expect(find.text(column), findsOneWidget);
      }

      // First page: 50 rows, each with its role control.
      expect(find.text('user-001'), findsOneWidget);
      expect(find.text('user-050'), findsOneWidget);
      expect(find.text('user-051'), findsNothing);
      expect(find.byTooltip('Change roles'), findsNWidgets(50));
      expect(find.text('admin'), findsOneWidget);
      expect(find.text('1–50 of 120'), findsOneWidget);

      // A null createdDate renders as a dash, not "null".
      expect(find.text('—'), findsOneWidget);
      expect(find.text('null'), findsNothing);

      // No tags or projectsOwned (a server before tercen/sci#1664): those
      // cells are blank, not 0 and not "unknown".
      expect(_rowTexts(tester, 'user-002'), [
        'user-002',
        'user2@example.test',
        'north',
        '2026-09-01 12:00',
      ]);
      expect(_rowTexts(tester, 'user-003'), [
        'user-003',
        'user3@example.test',
        'default',
        '2026-09-01 12:00',
      ]);
      expect(find.byKey(const Key('projects-owned-unknown')), findsNothing);

      await _nextPage(tester);
      await tester.pumpAndSettle();
      expect(find.text('user-001'), findsNothing);
      expect(find.text('user-051'), findsOneWidget);
      expect(find.text('51–100 of 120'), findsOneWidget);

      await _unmount(tester);
    });

    testWidgets('says when the server truncated the list', (tester) async {
      await _pump(tester,
          {'rows': _rows(1000), 'total': 1840, 'truncated': true});

      expect(_banner(tester),
          'Showing 1000 of 1840 users — the server returned only the first '
          '1000');
      await _unmount(tester);
    });

    testWidgets('truncated with no total does not blame the limit',
        (tester) async {
      // 480 rows is not the limit of 1000: the server said the list is
      // incomplete and nothing more, so the line says only that.
      await _pump(tester, {'rows': _rows(480), 'truncated': true});

      expect(_banner(tester),
          'Showing 480 of the first 480 users — the server reported the list '
          'as incomplete; it does not report a total');
      expect(_banner(tester), isNot(contains('limit')));
      await _unmount(tester);
    });

    testWidgets('grants and revokes a role from a row on page 3',
        (tester) async {
      final data = await _pump(tester,
          {'rows': _rows(150), 'total': 150, 'truncated': false});

      await tester.ensureVisible(find.byTooltip('Last page'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Last page'));
      await tester.pumpAndSettle();
      expect(find.text('101–150 of 150'), findsOneWidget);

      /// The role menu on user-120's row: the one level with its name.
      Finder roleMenu() {
        final nameY = tester.getCenter(find.text('user-120')).dy;
        final menus = find.byTooltip('Change roles');
        final index = List.generate(menus.evaluate().length, (i) => i)
            .firstWhere(
                (i) => (tester.getCenter(menus.at(i)).dy - nameY).abs() < 4);
        return menus.at(index);
      }

      Future<void> pick(String role) async {
        await tester.ensureVisible(roleMenu());
        await tester.pumpAndSettle();
        await tester.tap(roleMenu());
        await tester.pumpAndSettle();
        await tester.tap(find.descendant(
            of: find.byType(PopupMenuItem<String>),
            matching: find.text(role)));
        await tester.pumpAndSettle();
      }

      /// After the refresh the page is kept and user-120's row is on it.
      void expectPageKept() {
        expect(find.text('101–150 of 150'), findsOneWidget);
        expect(find.text('user-101'), findsOneWidget);
        expect(find.text('user-120'), findsOneWidget);
        expect(find.text('user-001'), findsNothing);
      }

      expect(find.text('operator'), findsNothing);
      data.client.calls.clear();
      await pick('operator');

      expect(data.client.calls, ['grantRole user-120 operator', 'listUsers']);
      expectPageKept();
      // The new chip sits in user-120's row.
      expect(find.text('operator'), findsOneWidget);
      expect(
          (tester.getCenter(find.text('operator')).dy -
                  tester.getCenter(find.text('user-120')).dy)
              .abs(),
          lessThan(4));

      data.client.calls.clear();
      await pick('operator');

      expect(data.client.calls, ['revokeRole user-120 operator', 'listUsers']);
      expectPageKept();
      expect(find.text('operator'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('the filter counts what is left and returns to page one',
        (tester) async {
      await _pump(tester,
          {'rows': _rows(120), 'total': 120, 'truncated': false});
      await _nextPage(tester);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('users-search')), 'user-11');
      await tester.pumpAndSettle();

      // user-110…119.
      expect(_banner(tester), 'Showing 10 of 120 users');
      expect(find.text('user-110'), findsOneWidget);
      expect(find.text('1–10 of 10'), findsOneWidget);
      await _unmount(tester);
    });
  });

  group('old response shape (rows only)', () {
    testWidgets('counts what it loaded and says the total is unreported',
        (tester) async {
      await _pump(tester, {'rows': _rows(12)});

      expect(_banner(tester),
          'Showing 12 of 12 users loaded; this server does not report a total');
      expect(find.text('user-012'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);

      // Every column is there; the ones this server cannot fill are blank.
      for (final column in ['ROLES', 'PROJECTS\nOWNED', 'TAGS']) {
        expect(find.text(column), findsOneWidget);
      }
      expect(find.byTooltip('Change roles'), findsNWidgets(12));
      expect(_rowTexts(tester, 'user-012'), [
        'user-012',
        'user12@example.test',
        'north',
        '2026-09-01 12:00',
      ]);
      expect(find.byKey(const Key('projects-owned-unknown')), findsNothing);

      // A list that fits one page puts the pager right under its last row,
      // not a full empty page below it.
      final lastRow = tester.getBottomLeft(find.text('user-012')).dy;
      final pager = tester.getTopLeft(find.text('1–12 of 12')).dy;
      expect(pager - lastRow, lessThan(60));
      await _unmount(tester);
    });

    testWidgets('a list that fills the limit may have stopped there',
        (tester) async {
      await _pump(tester, {'rows': _rows(1000)});

      expect(_banner(tester),
          'Showing 1000 of the first 1000 users — the list stopped at the '
          'limit of 1000; this server does not report a total');
      await _unmount(tester);
    });
  });

  group('tags and projectsOwned (tercen/sci#1664)', () {
    testWidgets('renders the count, 0, unknown and the tags', (tester) async {
      await _pump(tester,
          {'rows': _w3Rows(), 'total': 3, 'truncated': false});

      expect(_banner(tester), 'Showing 3 of 3 users');
      expect(_rowTexts(tester, 'user-a'), [
        'user-a',
        'user-a@example.test',
        'default',
        '2026-09-01 12:00',
        '4',
        'pilot',
        'beta',
      ]);
      // Counted, none owned: 0. Empty tags: nothing.
      expect(_rowTexts(tester, 'user-b'), [
        'user-b',
        'user-b@example.test',
        'north',
        '2026-09-01 12:00',
        '0',
      ]);
      // Not counted: "unknown", not 0 and not blank.
      expect(_rowTexts(tester, 'user-c'), [
        'user-c',
        'user-c@example.test',
        'north',
        '2026-09-01 12:00',
        'unknown',
        'beta',
      ]);
      expect(find.text('null'), findsNothing);

      // And it looks different from a count.
      final unknown = tester.widget<Text>(
          find.byKey(const Key('projects-owned-unknown')));
      final zero = tester.widget<Text>(find.text('0'));
      expect(unknown.style?.fontStyle, FontStyle.italic);
      expect(zero.style?.fontStyle, isNot(FontStyle.italic));
      expect(find.byTooltip(
              'The server could not count the projects in this instance'),
          findsOneWidget);

      // The role controls are still on every row.
      expect(find.byTooltip('Change roles'), findsNWidgets(3));
      await _unmount(tester);
    });

    test('fromJson keeps absent, null and 0 apart', () {
      final absent = DashboardUser.fromJson({'name': 'x'});
      expect(absent.projectsOwnedReported, isFalse);
      expect(absent.projectsOwned, isNull);
      expect(absent.tags, isNull);
      expect(absent.domain, '');

      final unknown =
          DashboardUser.fromJson({'name': 'x', 'projectsOwned': null});
      expect(unknown.projectsOwnedReported, isTrue);
      expect(unknown.projectsOwned, isNull);

      final zero = DashboardUser.fromJson({
        'name': 'x',
        'domain': 'north',
        'projectsOwned': 0,
        'tags': <String>[],
      });
      expect(zero.projectsOwnedReported, isTrue);
      expect(zero.projectsOwned, 0);
      expect(zero.tags, isEmpty);
      expect(zero.domain, 'north');
    });

    test('fromJson drops null and non-string tags', () {
      final user = DashboardUser.fromJson({
        'name': 'x',
        'tags': ['pilot', null, 7, '', true, 'beta'],
      });
      expect(user.tags, ['pilot', 'beta']);
    });

    testWidgets('a null tag is not a "null" chip', (tester) async {
      final rows = _w3Rows();
      rows[0]['tags'] = [null, 'pilot', 42];
      await _pump(tester, {'rows': rows, 'total': 3, 'truncated': false});

      expect(_rowTexts(tester, 'user-a').skip(4), ['4', 'pilot']);
      expect(find.text('null'), findsNothing);
      expect(find.text('42'), findsNothing);
      await _unmount(tester);
    });

    // Unbounded, 30 tags or one 300-character tag made the table several
    // thousand pixels wide. Bounded, it is at most one Tags cell (two
    // chips and a "+N") wider than the same table with no tags at all.
    for (final (label, tags) in [
      ('30 tags', [for (var i = 1; i <= 30; i++) 'tag-$i']),
      ('one 300-character tag', ['x' * 300]),
    ]) {
      testWidgets('$label keep the table width bounded', (tester) async {
        const maxCell = 3 * 80.0 + 2 * 4;
        final untagged = [
          for (final row in _w3Rows()) {...row, 'tags': <String>[]},
        ];
        await _pump(
            tester, {'rows': untagged, 'total': 3, 'truncated': false});
        final base = tester.getSize(find.byType(DataTable)).width;
        await _unmount(tester);

        final rows = _w3Rows();
        rows[0]['tags'] = tags;
        rows[2]['tags'] = <String>[];
        await _pump(tester, {'rows': rows, 'total': 3, 'truncated': false});

        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(DataTable)).width,
            lessThanOrEqualTo(base + maxCell));
        // The cell: at most two chips and a "+N", each chip bounded.
        final cell = find.ancestor(
            of: find.text(tags.first), matching: find.byType(Tooltip));
        expect(tester.getSize(cell).width, lessThanOrEqualTo(maxCell));
        for (final tag in tags.take(2)) {
          expect(tester.getSize(find.text(tag)).width, lessThan(80));
        }
        if (tags.length > 2) {
          expect(find.text('tag-3'), findsNothing);
          expect(
              tester.widget<Text>(find.descendant(
                  of: find.byKey(const Key('tags-more')),
                  matching: find.byType(Text))).data,
              '+28');
        } else {
          expect(find.byKey(const Key('tags-more')), findsNothing);
        }
        // The full list is still there, as the cell's tooltip.
        expect(find.byTooltip(tags.join(', ')), findsOneWidget);
        await _unmount(tester);
      });
    }
  });

  group('activity columns (tercen/sci#1667)', () {
    /// The URL of every link in the table, top to bottom.
    List<String> links(WidgetTester tester) => [
          for (final link
              in tester.widgetList<LinkText>(find.byType(LinkText)))
            link.url,
        ];

    testWidgets('the list shows at once; the activity cells load after it',
        (tester) async {
      final gate = Completer<void>();
      final data = await _pump(tester, _w3Report(),
          activity: _activity(), gate: gate.future);

      // listUsers is on screen, every row with its role control, while
      // listUserActivity has not answered.
      expect(_banner(tester), 'Showing 3 of 3 users');
      expect(find.text('user-a'), findsOneWidget);
      expect(find.byTooltip('Change roles'), findsNWidgets(3));
      expect(find.text('LAST\nWORKED ON'), findsOneWidget);
      expect(find.text('ACTIVE\nDAYS'), findsOneWidget);
      // Three rows, two activity cells each, all loading.
      expect(find.byKey(const Key('activity-loading')), findsNWidgets(6));
      expect(_status(tester),
          'Loading activity — the table can be used meanwhile');
      expect(_rowTexts(tester, 'user-a'), [
        'user-a',
        'user-a@example.test',
        'default',
        '2026-09-01 12:00',
        '…',
        '…',
        '4',
        'pilot',
        'beta',
      ]);

      // The table is usable meanwhile: the filter narrows it, the role
      // menu opens.
      await tester.enterText(find.byKey(const Key('users-search')), 'user-b');
      await tester.pump();
      expect(_banner(tester), 'Showing 1 of 3 users');
      expect(find.text('user-a'), findsNothing);
      await tester.tap(find.byTooltip('Change roles'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(PopupMenuItem<String>), findsNWidgets(3));
      await tester.tapAt(const Offset(4, 4));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byKey(const Key('users-search')), '');
      await tester.pump();

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('activity-loading')), findsNothing);
      expect(find.byKey(const Key('activity-status')), findsNothing);
      expect(_rowTexts(tester, 'user-a'), [
        'user-a',
        'user-a@example.test',
        'default',
        '2026-09-01 12:00',
        'Gating',
        '+9',
        '40',
        '4',
        'pilot',
        'beta',
      ]);
      // All time: empty from and to, the server's default budget.
      expect(data.client.activityParams, [
        {'from': '', 'to': '', 'budget': 0},
      ]);
      await _unmount(tester);
    });

    testWidgets('loaded: the latest object links to it; counts as sent',
        (tester) async {
      await _pump(tester, _w3Report(), activity: _activity());

      expect(links(tester), ['https://tercen.example/team-x/w/wf-a1']);
      // No window: no Days in window column.
      expect(find.text('DAYS IN\nWINDOW'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('expands in place to the last ten objects and collapses',
        (tester) async {
      await _pump(tester, _w3Report(), activity: _activity());
      final collapsed = tester.getSize(find.byType(DataTable)).height;
      expect(find.byKey(const Key('activity-expanded')), findsNothing);
      expect(find.text('Pilot'), findsNothing);

      await tester.tap(find.byKey(const Key('activity-toggle')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final open = find.byKey(const Key('activity-expanded'));
      expect(open, findsOneWidget);
      // In the row, not somewhere else: the table grew around it.
      expect(tester.getSize(find.byType(DataTable)).height,
          greaterThan(collapsed));
      // Ten entries, each with its details on hover.
      expect(find.descendant(of: open, matching: find.byType(Tooltip)),
          findsNWidgets(10));
      for (final name in [
        'Gating',
        'Pilot',
        'Old flow',
        'plate.csv',
        for (var i = 5; i <= 10; i++) 'Flow $i',
      ]) {
        expect(find.descendant(of: open, matching: find.text(name)),
            findsOneWidget,
            reason: name);
      }
      // Every link, on its exact URL: a workflow at /<owner>/w/<id>,
      // anything else at its project's /<owner>/p/<projectId>. The owner
      // is the entry's, not the user's.
      expect(links(tester), [
        'https://tercen.example/team-x/w/wf-a1',
        'https://tercen.example/user-a/p/pr-2',
        for (var i = 5; i <= 10; i++) 'https://tercen.example/team-x/w/wf-a$i',
      ]);
      // owner null: plain text, no link.
      expect(
          find.ancestor(
              of: find.text('plate.csv'), matching: find.byType(LinkText)),
          findsNothing);
      // Deleted: struck through, marked, and not linked.
      final deleted = tester.widget<Text>(find.text('Old flow'));
      expect(deleted.style?.decoration, TextDecoration.lineThrough);
      expect(find.byKey(const Key('activity-deleted')), findsOneWidget);
      expect(
          find.ancestor(
              of: find.text('Old flow'), matching: find.byType(LinkText)),
          findsNothing);

      await tester.tap(find.byKey(const Key('activity-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('activity-expanded')), findsNothing);
      expect(find.text('Pilot'), findsNothing);
      expect(find.text('+9'), findsOneWidget);
      expect(tester.getSize(find.byType(DataTable)).height, collapsed);
      await _unmount(tester);
    });

    testWidgets('an open row stays open on a later page and back',
        (tester) async {
      // Open on page 1, go to page 2 and back: still open.
      final rows = [
        ..._w3Rows(),
        for (var i = 1; i <= 60; i++)
          {
            'id': 'id-extra-$i',
            'name': 'extra-${i.toString().padLeft(2, '0')}',
            'email': 'extra$i@example.test',
            'domain': 'north',
            'roles': ['user'],
            'isValidated': true,
            'createdDate': '2026-09-01T12:00:00',
          },
      ];
      await _pump(tester, {'rows': rows, 'total': 63, 'truncated': false},
          activity: _activity());
      await tester.tap(find.byKey(const Key('activity-toggle')));
      await tester.pumpAndSettle();
      await _nextPage(tester);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('51–63 of 63'), findsOneWidget);
      expect(find.byKey(const Key('activity-expanded')), findsNothing);
      await tester.ensureVisible(find.byTooltip('Previous page'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Previous page'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('activity-expanded')), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('null is unknown and looks it; 0 and none are values',
        (tester) async {
      await _pump(tester, _w3Report(), activity: _activity());

      // Counted, nothing found: "none" and 0.
      expect(_rowTexts(tester, 'user-b').sublist(4), ['none', '0', '0']);
      // Not read: "unknown" in both cells, never 0 or blank.
      expect(_rowTexts(tester, 'user-c').sublist(4),
          ['unknown', 'unknown', 'unknown', 'beta']);
      final unknown = tester.widget<Text>(find.descendant(
          of: find.byKey(const Key('active-days-unknown')),
          matching: find.byType(Text)));
      expect(unknown.style?.fontStyle, FontStyle.italic);
      final zero = tester.widgetList<Text>(find.text('0')).first;
      expect(zero.style?.fontStyle, isNot(FontStyle.italic));
      expect(find.byKey(const Key('recent-unknown')), findsOneWidget);
      expect(find.byTooltip("The server could not read this user's activity"),
          findsNWidgets(2));
      expect(find.text('null'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('a truncated count is a lower bound, marked ≥',
        (tester) async {
      final activity = _activity(window: ('2026-08-01', '2026-08-31'));
      final a = (activity['rows'] as List).first as Map<String, Object?>;
      a['truncated'] = true;
      a['windowTruncated'] = true;
      final b = (activity['rows'] as List)[1] as Map<String, Object?>;
      b['activeDays'] = 3;
      b['activeDaysInWindow'] = 2;
      final data = await _pump(tester, _w3Report(),
          activity: activity,
          filters: const UserFilters(
              mode: WindowMode.custom, from: '2026-08-01', to: '2026-08-31'));

      // The window goes to the server, and the column shows.
      expect(data.client.activityParams, [
        {'from': '2026-08-01', 'to': '2026-08-31', 'budget': 0},
      ]);
      expect(find.text('DAYS IN\nWINDOW'), findsOneWidget);
      expect(find.byTooltip('Days with activity, 2026-08-01 – 2026-08-31 (UTC)'),
          findsOneWidget);
      // Truncated: "≥", with the reason on hover.
      expect(_rowTexts(tester, 'user-a').sublist(5, 8), ['+9', '≥40', '≥7']);
      expect(find.byTooltip(RegExp(r'^At least 40: ')), findsOneWidget);
      expect(find.byTooltip(RegExp(r'^At least 7: ')), findsOneWidget);
      // Not truncated: the plain count.
      expect(_rowTexts(tester, 'user-b').sublist(4, 7), ['none', '3', '2']);
      await _unmount(tester);
    });

    testWidgets('a new window reloads the activity', (tester) async {
      final data = await _pump(tester, _w3Report(), activity: _activity());
      data.client.activity = _activity(window: ('2026-09-01', '2026-09-30'));
      await _chooseWindow(tester, '2026-09-01', '2026-09-30');

      expect(data.client.activityParams, [
        {'from': '', 'to': '', 'budget': 0},
        {'from': '2026-09-01', 'to': '2026-09-30', 'budget': 0},
      ]);
      expect(_rowTexts(tester, 'user-a').sublist(6, 8), ['40', '7']);
      await _unmount(tester);
    });

    /// [_activity] for all time, but with user-a on 111 active days: a
    /// value only the first, superseded request carries.
    Map<String, Object?> staleActivity() {
      final activity = _activity();
      ((activity['rows'] as List).first as Map<String, Object?>)['activeDays'] =
          111;
      return activity;
    }

    /// The page asks for all time (request 0, held), then moves to a
    /// window (request 1, held); request 1 answers first.
    Future<_ReportData> supersede(WidgetTester tester) async {
      final data = await _pump(tester, _w3Report(), hold: true);
      await _chooseWindow(tester, '2026-09-01', '2026-09-30', settle: false);
      expect(data.client.held, hasLength(2));
      data.client
          .answerHeld(1, _activity(window: ('2026-09-01', '2026-09-30')));
      await tester.pumpAndSettle();
      expect(_rowTexts(tester, 'user-a').sublist(6, 9), ['40', '7', '4']);
      return data;
    }

    testWidgets('a late answer to a superseded window is dropped',
        (tester) async {
      final data = await supersede(tester);

      data.client.answerHeld(0, staleActivity());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // The window's values stay; the old request's never show.
      expect(_rowTexts(tester, 'user-a').sublist(6, 9), ['40', '7', '4']);
      expect(find.text('111'), findsNothing);
      expect(find.byKey(const Key('activity-status')), findsNothing);
      await _unmount(tester);
    });

    testWidgets('a late failure of a superseded window is dropped',
        (tester) async {
      final data = await supersede(tester);

      data.client.failHeld(0);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // No error icon in the cells and no error line over the values.
      expect(find.byKey(const Key('activity-error')), findsNothing);
      expect(find.byKey(const Key('activity-status')), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(_rowTexts(tester, 'user-a').sublist(6, 9), ['40', '7', '4']);
      await _unmount(tester);
    });

    /// Mounts the page with its request held, unmounts it, then lets
    /// [answer] complete the request.
    Future<void> answerAfterUnmount(
        WidgetTester tester, void Function(_ReportClient) answer) async {
      final data = await _pump(tester, _w3Report(), hold: true);
      expect(data.client.held, hasLength(1));
      await _unmount(tester);
      answer(data.client);
      await tester.pumpAndSettle();
    }

    testWidgets('a value after the page is gone is dropped quietly',
        (tester) async {
      await answerAfterUnmount(tester, (c) => c.answerHeld(0, _activity()));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an error after the page is gone is dropped quietly',
        (tester) async {
      await answerAfterUnmount(tester, (c) => c.failHeld(0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an error shows in the cells, the table works, retry loads',
        (tester) async {
      final data = await _pump(tester, _w3Report(),
          activity: _activity(), activityStatus: 500);

      expect(find.byKey(const Key('activity-error')), findsNWidgets(6));
      expect(_status(tester), startsWith('Activity could not be loaded: '));
      expect(_rowTexts(tester, 'user-a'), [
        'user-a',
        'user-a@example.test',
        'default',
        '2026-09-01 12:00',
        '4',
        'pilot',
        'beta',
      ]);
      expect(find.byTooltip('Change roles'), findsNWidgets(3));

      data.client.activityStatus = 200;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('activity-error')), findsNothing);
      expect(_rowTexts(tester, 'user-a').sublist(4, 7), ['Gating', '+9', '40']);
      expect(data.client.activityParams, hasLength(2));
      await _unmount(tester);
    });

    testWidgets('a server without listUserActivity: blank cells, a note',
        (tester) async {
      final data = await _pump(tester, _w3Report());

      expect(data.client.activityParams, hasLength(1));
      expect(_status(tester),
          'This server does not report user activity; those columns are '
          'blank');
      expect(find.byKey(const Key('activity-error')), findsNothing);
      expect(find.byKey(const Key('activity-loading')), findsNothing);
      // Every other cell as before; the activity cells are empty.
      expect(_rowTexts(tester, 'user-a'), [
        'user-a',
        'user-a@example.test',
        'default',
        '2026-09-01 12:00',
        '4',
        'pilot',
        'beta',
      ]);
      expect(find.byTooltip('Change roles'), findsNWidgets(3));
      await _unmount(tester);
    });

    test('fromJson keeps null apart from 0 and drops an empty owner', () {
      final report = UserActivityReport.fromJson(_activity());
      final a = report[('', 'id-user-a')]!;
      expect(a.activeDays, 40);
      expect(a.activeDaysInWindow, isNull);
      expect(a.recent, hasLength(10));
      expect(a.recent![2].isDeleted, isTrue);
      expect(a.recent![3].owner, isNull);
      final b = report[('north', 'id-user-b')]!;
      expect(b.activeDays, 0);
      expect(b.recent, isEmpty);
      final c = report[('north', 'id-user-c')]!;
      expect(c.activeDays, isNull);
      expect(c.recent, isNull);
      // A user is named by domain and id together.
      expect(report[('', 'id-user-b')], isNull);
      expect(report.window, isNull);
      expect(
          ActivityObject.fromJson({'kind': 'Workflow', 'owner': ''}).owner,
          isNull);
    });
  });

  group('UserListing.mayHaveMore', () {
    DashboardUser user(int i) =>
        DashboardUser.fromJson({'id': 'id-$i', 'name': 'user-$i'});

    test('trusts truncated when the server sends it', () {
      final users = [user(1)];
      expect(
          UserListing(users: users, viaFallback: false, total: 1, truncated: true)
              .mayHaveMore,
          isTrue);
      expect(
          UserListing(
                  users: users, viaFallback: false, total: 9, truncated: false)
              .mayHaveMore,
          isFalse);
    });

    test('compares with total when truncated is absent', () {
      final users = [user(1), user(2)];
      expect(UserListing(users: users, viaFallback: false, total: 3).mayHaveMore,
          isTrue);
      expect(UserListing(users: users, viaFallback: false, total: 2).mayHaveMore,
          isFalse);
    });

    test('with neither, a full page may have more', () {
      final users = [user(1), user(2)];
      expect(
          UserListing(users: users, viaFallback: true, limit: 2).mayHaveMore,
          isTrue);
      expect(
          UserListing(users: users, viaFallback: true, limit: 3).mayHaveMore,
          isFalse);
    });
  });

  group('filter bar (activity window, MAU, email-domain exclusion)', () {
    /// Invented users for the filters, with the windowed count each has in
    /// the answer. The email domain is what an exclusion matches, not the
    /// Domain column: `col` sits in a Domain named `example.test`.
    const people = [
      // name, email, Domain column, days in window, windowTruncated
      ('act-1', 'act-1@lab.example', '', 3, false),
      ('act-2', 'act-2@Example.TEST', '', 5, false),
      ('idle', 'idle@lab.example', 'north', 0, false),
      ('unread', 'unread@lab.example', 'north', null, null),
      ('lower', 'lower@lab.example', '', 2, true),
      ('lower-0', 'lower-0@lab.example', '', 0, true),
      ('sub', 'sub@sub.example.test', 'north', 4, false),
      ('col', 'col@lab.example', 'example.test', 1, false),
      ('act-3', 'act-3@example.test', 'north', 9, false),
    ];

    Map<String, Object?> report() => {
          'rows': [
            for (final (name, email, domain, _, _) in people)
              {
                'id': 'id-$name',
                'name': name,
                'email': email,
                'domain': domain,
                'roles': ['user'],
                'isValidated': true,
                'createdDate': '2026-09-01T12:00:00',
              }
          ],
          'total': people.length,
          'truncated': false,
        };

    /// listUserActivity's answer: the counts in [people], over [window].
    Map<String, Object?> activity((String, String) window) => {
          'budget': 20000,
          'window': {'from': window.$1, 'to': window.$2},
          'rows': [
            for (final (name, _, domain, days, cut) in people)
              {
                'id': 'id-$name',
                'name': name,
                'domain': domain,
                'activeDays': days == null ? null : days + 10,
                'activeDaysInWindow': days,
                'recent': <Object>[],
                'truncated': false,
                'windowTruncated': cut,
              }
          ],
        };

    /// The names on the page, in [people]'s order (the list's order).
    List<String> names(WidgetTester tester) => [
          for (final (name, _, _, _, _) in people)
            if (find.text(name).evaluate().isNotEmpty) name,
        ];

    String note(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const Key('mau-note'))).data!;

    ChoiceChip chip(WidgetTester tester, String key) =>
        tester.widget<ChoiceChip>(find.byKey(Key(key)));

    Future<void> exclude(WidgetTester tester, String typed) async {
      await tester.enterText(find.byKey(const Key('filter-exclude')), typed);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }

    const mauWindow = ('2026-09-16', '2026-10-15');

    group('UserFilters', () {
      test('MAU is the last 30 UTC days, today included', () {
        const mau = UserFilters(mode: WindowMode.mau);
        expect(mau.window(DateTime.utc(2026, 10, 15, 23, 59)),
            const ActivityWindow('2026-09-16', '2026-10-15'));
        expect(mau.window(DateTime.utc(2026, 10, 15)),
            const ActivityWindow('2026-09-16', '2026-10-15'));
        // Across a month end and February.
        expect(mau.window(DateTime.utc(2026, 3, 1, 0, 30)),
            const ActivityWindow('2026-01-31', '2026-03-01'));
        // A local clock counts on its UTC day.
        final local = DateTime.utc(2026, 10, 15, 23, 30).toLocal();
        expect(mau.window(local).to, '2026-10-15');
      });

      test('all time and a custom window', () {
        expect(const UserFilters().window(DateTime.utc(2026)).isAllTime,
            isTrue);
        expect(
            const UserFilters(
                    mode: WindowMode.custom, from: '2026-01-02', to: '2026-02-03')
                .window(DateTime.utc(2026, 10, 15)),
            const ActivityWindow('2026-01-02', '2026-02-03'));
      });

      test('the email domain decides, case-insensitive and exact', () {
        const f = UserFilters(excluded: ['example.test']);
        DashboardUser u(String email, {String domain = ''}) => DashboardUser(
            id: 'i',
            name: 'n',
            email: email,
            domain: domain,
            roles: const [],
            isValidated: true,
            createdDate: '');
        expect(f.excludes(u('a@example.test')), isTrue);
        expect(f.excludes(u('a@EXAMPLE.Test')), isTrue);
        expect(f.excludes(u('a@sub.example.test')), isFalse);
        expect(f.excludes(u('a@lab.example', domain: 'example.test')), isFalse);
        expect(f.excludes(u('no-at-sign')), isFalse);
        expect(normalizeDomain('  @Example.TEST '), 'example.test');
      });

      test('round-trips; what it cannot read falls back to the default', () {
        final settings = MemorySettings();
        const f = UserFilters(
            mode: WindowMode.custom,
            from: '2026-08-01',
            to: '2026-08-31',
            excluded: ['example.test']);
        f.save(settings);
        final back = UserFilters.load(settings);
        expect((back.mode, back.from, back.to),
            (WindowMode.custom, '2026-08-01', '2026-08-31'));
        expect(back.excluded, ['example.test']);

        for (final stored in [
          '',
          'not json',
          '[1, 2]',
          '{"mode": "someday"}',
          '{"mode": "custom", "from": "2026-08-31", "to": "2026-08-01"}',
          '{"mode": "custom", "from": "yesterday", "to": "2026-08-01"}',
        ]) {
          final f = UserFilters.load(
              MemorySettings({UserFilters.storageKey: stored}));
          expect(f.mode, WindowMode.allTime, reason: stored);
          expect(f.excluded, isEmpty, reason: stored);
        }
        final mixed = UserFilters.load(MemorySettings({
          UserFilters.storageKey:
              '{"mode": "mau", "excluded": ["@A.example", 3, null, "", "a.example"]}'
        }));
        expect(mixed.mode, WindowMode.mau);
        expect(mixed.excluded, ['a.example']);
      });

      test('in the window: active, inactive, or unknown — never guessed', () {
        UserActivity a(int? days, {bool cut = false}) => UserActivity(
            id: 'i',
            name: 'n',
            domain: '',
            activeDaysInWindow: days,
            windowTruncated: cut);
        expect(windowActivity(a(3)), WindowActivity.active);
        expect(windowActivity(a(2, cut: true)), WindowActivity.active);
        expect(windowActivity(a(0)), WindowActivity.inactive);
        expect(windowActivity(a(0, cut: true)), WindowActivity.unknown);
        expect(windowActivity(a(null)), WindowActivity.unknown);
        expect(windowActivity(null), WindowActivity.unknown);
      });

      test('the banner leaves the excluded out of every count', () {
        List<DashboardUser> users(int n) => [
              for (var i = 0; i < n; i++)
                DashboardUser(
                    id: '$i',
                    name: '$i',
                    email: '',
                    domain: '',
                    roles: const [],
                    isValidated: true,
                    createdDate: ''),
            ];
        expect(
            showingBanner(
                UserListing(
                    users: users(10), viaFallback: false, total: 10,
                    truncated: false),
                7,
                excluded: 2),
            'Showing 7 of 8 users (2 excluded by email domain)');
        // Part of the list: the unreturned users' domains are unknown.
        expect(
            showingBanner(
                UserListing(
                    users: users(10), viaFallback: false, total: 40,
                    truncated: true),
                7,
                excluded: 2),
            'Showing 7 of the first 8 users (2 excluded by email domain) — '
            'the server returned only the first 10 of 40');
        expect(
            showingBanner(
                UserListing(users: users(10), viaFallback: true, limit: 50),
                7,
                excluded: 2),
            'Showing 7 of 8 users loaded (2 excluded by email domain); this '
            'server does not report a total');
      });
    });

    testWidgets(
        'MAU: exactly the non-excluded users active in the last 30 days',
        (tester) async {
      final data = await _pump(tester, report(),
          activity: activity(mauWindow),
          filters: const UserFilters(excluded: ['example.test']));
      expect(data.client.activityParams.single,
          {'from': '', 'to': '', 'budget': 0});

      await tester.tap(find.byKey(const Key('filter-mau')));
      await tester.pumpAndSettle();

      // Asked for today and the 29 days before it, UTC (the clock is
      // 15 October 2026, 12:00 UTC).
      expect(data.client.activityParams.last,
          {'from': '2026-09-16', 'to': '2026-10-15', 'budget': 0});
      expect(chip(tester, 'filter-mau').selected, isTrue);
      // Active and kept: at least one day in the window, a lower bound of
      // 2 included; `sub` and `col` are not @example.test. Left out:
      // act-2 and act-3 (@example.test), idle (0 days), and unread and
      // lower-0, whose activity could not be counted.
      expect(names(tester), ['act-1', 'lower', 'sub', 'col']);
      expect(_banner(tester),
          'Showing 4 of 7 users (2 excluded by email domain)');
      expect(
          note(tester),
          'MAU, 2026-09-16 – 2026-10-15 (UTC): users active in the window — '
          '4 to 6: 2 more users whose activity in the window could not be '
          'counted are not shown');
      // The windowed column shows, the lower bound marked.
      expect(find.text('DAYS IN\nWINDOW'), findsOneWidget);
      expect(find.text('≥2'), findsOneWidget);

      // Back to all time: every non-excluded user, no MAU line.
      await tester.tap(find.byKey(const Key('filter-all-time')));
      await tester.pumpAndSettle();
      expect(data.client.activityParams.last,
          {'from': '', 'to': '', 'budget': 0});
      expect(names(tester),
          ['act-1', 'idle', 'unread', 'lower', 'lower-0', 'sub', 'col']);
      expect(find.byKey(const Key('mau-note')), findsNothing);
      expect(find.text('DAYS IN\nWINDOW'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('MAU while the activity loads: the list is not narrowed yet',
        (tester) async {
      final data = await _pump(tester, report(),
          hold: true, filters: const UserFilters(mode: WindowMode.mau));
      expect(data.client.activityParams.single,
          {'from': '2026-09-16', 'to': '2026-10-15', 'budget': 0});
      expect(names(tester), hasLength(people.length));
      expect(note(tester), startsWith('MAU, 2026-09-16 – 2026-10-15 (UTC): '
          'waiting for the activity'));

      data.client.answerHeld(0, activity(mauWindow));
      await tester.pumpAndSettle();
      expect(names(tester), ['act-1', 'act-2', 'lower', 'sub', 'col', 'act-3']);
      expect(_banner(tester), 'Showing 6 of 9 users');
      await _unmount(tester);
    });

    testWidgets('MAU pressed while a request is out: the old answer is dropped',
        (tester) async {
      final data = await _pump(tester, report(), hold: true);
      await tester.tap(find.byKey(const Key('filter-mau')));
      await _pumpFrames(tester);
      expect(data.client.held, hasLength(2));

      data.client.answerHeld(1, activity(mauWindow));
      await tester.pumpAndSettle();
      expect(names(tester), ['act-1', 'act-2', 'lower', 'sub', 'col', 'act-3']);

      // The all-time answer, late: everyone "active" in it. Dropped.
      final stale = activity(mauWindow);
      for (final r in (stale['rows'] as List).cast<Map<String, Object?>>()) {
        r['activeDaysInWindow'] = 99;
        r['windowTruncated'] = false;
      }
      data.client.answerHeld(0, stale);
      await tester.pumpAndSettle();
      expect(names(tester), ['act-1', 'act-2', 'lower', 'sub', 'col', 'act-3']);
      expect(find.text('99'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('excluding example.test removes its rows from list and count',
        (tester) async {
      final data =
          await _pump(tester, report(), activity: activity(mauWindow));
      expect(_banner(tester), 'Showing 9 of 9 users');

      await exclude(tester, ' @Example.Test ');

      expect(find.byKey(const Key('excluded-example.test')), findsOneWidget);
      expect(names(tester),
          ['act-1', 'idle', 'unread', 'lower', 'lower-0', 'sub', 'col']);
      expect(_banner(tester),
          'Showing 7 of 7 users (2 excluded by email domain)');
      // The name search counts within what is left.
      await tester.enterText(find.byKey(const Key('users-search')), 'act');
      await tester.pumpAndSettle();
      expect(names(tester), ['act-1']);
      expect(_banner(tester),
          'Showing 1 of 7 users (2 excluded by email domain)');
      await tester.enterText(find.byKey(const Key('users-search')), '');
      await tester.pumpAndSettle();

      // An exclusion is no new window: nothing is fetched again.
      expect(data.client.activityParams, hasLength(1));

      // A second domain; the same one again is not added twice.
      await exclude(tester, 'lab.example');
      await exclude(tester, 'LAB.example');
      expect(names(tester), ['sub']);
      expect(_banner(tester),
          'Showing 1 of 1 users (8 excluded by email domain)');
      expect(find.byKey(const Key('excluded-lab.example')), findsOneWidget);

      // Removing the chips brings the rows back.
      await tester.tap(find.byTooltip('Include @lab.example again'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Include @example.test again'));
      await tester.pumpAndSettle();
      expect(_banner(tester), 'Showing 9 of 9 users');
      await _unmount(tester);
    });

    testWidgets('the settings persist and are restored on the next load',
        (tester) async {
      final settings = MemorySettings();
      await _pump(tester, report(),
          activity: activity(mauWindow), settings: settings);
      await tester.tap(find.byKey(const Key('filter-mau')));
      await tester.pumpAndSettle();
      await exclude(tester, 'example.test');
      expect(json.decode(settings.values[UserFilters.storageKey]!), {
        'mode': 'mau',
        'excluded': ['example.test'],
      });
      await _unmount(tester);

      // A new page on a later day: the MAU is counted to that day.
      final data = await _pump(tester, report(),
          activity: activity(('2026-09-22', '2026-10-21')),
          settings: settings,
          clock: DateTime.utc(2026, 10, 21, 8));
      expect(data.client.activityParams.single,
          {'from': '2026-09-22', 'to': '2026-10-21', 'budget': 0});
      expect(chip(tester, 'filter-mau').selected, isTrue);
      expect(find.byKey(const Key('excluded-example.test')), findsOneWidget);
      expect(names(tester), ['act-1', 'lower', 'sub', 'col']);
      await _unmount(tester);

      // A chosen window is kept as its days.
      final custom = await _pump(tester, report(),
          activity: activity(('2026-08-01', '2026-08-31')),
          settings: settings);
      await _chooseWindow(tester, '2026-08-01', '2026-08-31');
      expect(custom.client.activityParams.last,
          {'from': '2026-08-01', 'to': '2026-08-31', 'budget': 0});
      expect(tester.widget<Text>(find.descendant(
              of: find.byKey(const Key('filter-window')),
              matching: find.byType(Text))).data,
          '2026-08-01 – 2026-08-31');
      await _unmount(tester);
      final again = await _pump(tester, report(),
          activity: activity(('2026-08-01', '2026-08-31')),
          settings: settings);
      expect(again.client.activityParams.single,
          {'from': '2026-08-01', 'to': '2026-08-31', 'budget': 0});
      expect(chip(tester, 'filter-window').selected, isTrue);
      // Custom is not MAU: every non-excluded user, with their window days.
      expect(names(tester),
          ['act-1', 'idle', 'unread', 'lower', 'lower-0', 'sub', 'col']);
      await _unmount(tester);
    });

    testWidgets('an old server: MAU and the window are off, exclusion works',
        (tester) async {
      // Kept from a newer server: MAU and an exclusion.
      await _pump(tester, report(),
          filters: const UserFilters(
              mode: WindowMode.mau, excluded: ['example.test']));

      expect(chip(tester, 'filter-mau').onSelected, isNull);
      expect(chip(tester, 'filter-window').onSelected, isNull);
      expect(find.byTooltip('This server does not report user activity'),
          findsNWidgets(3));
      expect(note(tester),
          'MAU unavailable: this server does not report user activity');
      // No count to narrow by: every non-excluded user, no window column.
      expect(names(tester),
          ['act-1', 'idle', 'unread', 'lower', 'lower-0', 'sub', 'col']);
      expect(_banner(tester),
          'Showing 7 of 7 users (2 excluded by email domain)');
      expect(find.text('DAYS IN\nWINDOW'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('MAU when the activity fails: unavailable, not narrowed',
        (tester) async {
      await _pump(tester, report(),
          activity: activity(mauWindow),
          activityStatus: 500,
          filters: const UserFilters(mode: WindowMode.mau));
      expect(note(tester),
          'MAU unavailable: the activity could not be loaded, so the list is '
          'not narrowed to active users');
      expect(names(tester), hasLength(people.length));
      expect(find.text('Retry'), findsOneWidget);
      await _unmount(tester);
    });
  });
}
