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

/// Answers every POST with one listUsers report.
class _ReportClient implements http_api.HttpClient {
  final Map<String, Object?> report;
  _ReportClient(this.report);

  @override
  Future<http_api.Response> post(url,
          {Map<String, String>? headers,
          body,
          String? responseType,
          encoding,
          progressCallback}) async =>
      _FakeResponse(ContentCodec.tson().encode(json.encode(report)));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// The real [DashboardData.users], over a server that answers [report].
class _ReportData extends DashboardData {
  final Map<String, Object?> report;
  _ReportData(this.report) : super(fakeAdminSession());

  @override
  AdminApi get adminApi =>
      AdminApi(Uri.parse('https://tercen.example'), _ReportClient(report));
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

Future<void> _pump(WidgetTester tester, Map<String, Object?> report) async {
  tester.view
    ..physicalSize = const Size(1280, 1600)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: DashboardTheme.light,
    home: Scaffold(body: UsersScreen(data: _ReportData(report))),
  ));
  await tester.pumpAndSettle();
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
        'CREATED'
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
