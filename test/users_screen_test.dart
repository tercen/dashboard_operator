import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sci_http_client/content_codec.dart';
import 'package:sci_http_client/http_client.dart' as http_api;

import 'package:tercen_dashboard/src/admin_api.dart';
import 'package:tercen_dashboard/src/data.dart';
import 'package:tercen_dashboard/src/screens/users_screen.dart';
import 'package:tercen_dashboard/src/theme.dart';

import 'support/fake_data.dart';

class _FakeResponse implements http_api.Response {
  @override
  final int statusCode = 200;
  @override
  final Map? headers = const {};
  @override
  final Object? body;
  _FakeResponse(this.body);
}

/// Answers listUsers with [report], and grantRole/revokeRole as a server
/// would: the change is recorded in [report]'s rows, so the next listUsers
/// shows it, and the call answers with the user's new roles.
class _ReportClient implements http_api.HttpClient {
  final Map<String, Object?> report;
  final List<String> calls = [];
  _ReportClient(this.report);

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
    calls.add(endpoint);
    return _FakeResponse(codec.encode(json.encode(report)));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// The real [DashboardData.users] and [DashboardData.changeRole], over a
/// server that answers [report].
class _ReportData extends DashboardData {
  final _ReportClient client;
  _ReportData(Map<String, Object?> report)
      : client = _ReportClient(report),
        super(fakeAdminSession());

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

Future<_ReportData> _pump(
    WidgetTester tester, Map<String, Object?> report) async {
  final data = _ReportData(report);
  tester.view
    ..physicalSize = const Size(1280, 1600)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: DashboardTheme.light,
    home: Scaffold(body: UsersScreen(data: data)),
  ));
  await tester.pumpAndSettle();
  return data;
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

      await tester.enterText(find.byType(TextField), 'user-11');
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
}
