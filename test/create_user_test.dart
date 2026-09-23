import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sci_http_client/content_codec.dart';
import 'package:sci_http_client/http_client.dart' as http_api;
import 'package:sci_tercen_client/sci_client.dart' as sci;

import 'package:tercen_dashboard/src/admin_api.dart';
import 'package:tercen_dashboard/src/data.dart';
import 'package:tercen_dashboard/src/screens/create_user_dialog.dart';
import 'package:tercen_dashboard/src/screens/users_screen.dart';
import 'package:tercen_dashboard/src/session.dart';
import 'package:tercen_dashboard/src/theme.dart';

import 'support/fake_data.dart';

class _FakeResponse implements http_api.Response {
  @override
  final int statusCode;
  @override
  final Map? headers;
  @override
  final Object? body;
  _FakeResponse(this.body, {this.statusCode = 200, this.headers = const {}});
}

/// A server with invented users. listUsers answers [rows]; createUser adds
/// the user to them, first or with [appendCreated] last, and answers it —
/// or, when [refusal] is set, answers that error instead, as the server
/// reports one.
class _UsersClient implements http_api.HttpClient {
  final List<Map<String, Object?>> rows;
  final List<String> calls = [];
  final List<Map> created = [];
  final List<String> passwords = [];
  Map<String, Object?>? refusal;
  bool appendCreated = false;
  _UsersClient(this.rows);

  final _codec = ContentCodec.tson();

  @override
  Future<http_api.Response> post(url,
      {Map<String, String>? headers,
      body,
      String? responseType,
      encoding,
      progressCallback}) async {
    final endpoint = Uri.parse('$url').pathSegments.last;
    calls.add(endpoint);
    if (endpoint == 'createUser') {
      final params = _codec.decode(body) as Map;
      final user = Map.from(params['user'] as Map);
      created.add(user);
      passwords.add('${params['password']}');
      if (refusal != null) {
        return _FakeResponse(_codec.encode(refusal),
            statusCode: refusal!['statusCode'] as int,
            headers: {'content-type': _codec.contentType});
      }
      rows.insert(appendCreated ? rows.length : 0, {
        'id': user['name'],
        'name': user['name'],
        'email': user['email'],
        'domain': '',
        'roles': ['user'],
        'isValidated': user['isValidated'],
        'createdDate': '2026-09-23T09:00:00',
      });
      return _FakeResponse(_codec.encode(user));
    }
    return _FakeResponse(_codec.encode(
        json.encode({'rows': rows, 'total': rows.length, 'truncated': false})));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// The real [DashboardData.users] and [DashboardData.createUser] — the
/// pinned client's UserService — over [_UsersClient].
class _UsersData extends DashboardData {
  final _UsersClient client;
  _UsersData(super.session, this.client);

  static final _base = Uri.parse('https://tercen.example');

  static Future<_UsersData> create(
      DashboardSession session, List<Map<String, Object?>> rows) async {
    final client = _UsersClient(rows);
    session.factory = sci.ServiceFactory();
    await session.factory.initializeWith(_base, client);
    return _UsersData(session, client);
  }

  @override
  AdminApi get adminApi => AdminApi(_base, client);
}

List<Map<String, Object?>> _rows(
        [List<String> names = const ['ada', 'grace', 'linus']]) =>
    [
      for (final name in names)
        {
          'id': 'id-$name',
          'name': name,
          'email': '$name@example.test',
          'domain': '',
          'roles': ['user'],
          'isValidated': true,
          'createdDate': '2026-09-01T12:00:00',
        }
    ];

Future<_UsersData> _pump(WidgetTester tester,
    {DashboardSession? session, List<Map<String, Object?>>? rows}) async {
  final data = await _UsersData.create(
      session ?? fakeAdminSession(), rows ?? _rows());
  tester.view
    ..physicalSize = const Size(1280, 1000)
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

Future<void> _open(WidgetTester tester) async {
  // The button scrolls with the list: back to it, as the admin would.
  await tester.ensureVisible(find.text('Create user'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Create user'));
  await tester.pumpAndSettle();
  expect(find.byType(CreateUserDialog), findsOneWidget);
}

Future<void> _fill(WidgetTester tester,
    {String name = '', String email = '', String password = ''}) async {
  await tester.enterText(find.byKey(const Key('create-user-name')), name);
  await tester.enterText(find.byKey(const Key('create-user-email')), email);
  await tester.enterText(
      find.byKey(const Key('create-user-password')), password);
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Create'));
  await tester.pumpAndSettle();
}

/// 120 invented users: three pages of 50.
List<Map<String, Object?>> _manyRows() => _rows([
      for (var i = 1; i <= 120; i++) 'user-${'$i'.padLeft(3, '0')}',
    ]);

Future<void> _nextPage(WidgetTester tester) async {
  await tester.ensureVisible(find.byTooltip('Next page'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Next page'));
  await tester.pumpAndSettle();
}

/// [text] is built once and lies inside the scrolling list's viewport.
void _expectOnScreen(WidgetTester tester, String text) {
  final found = find.text(text);
  expect(found, findsOneWidget);
  final viewport = tester.getRect(find
      .ancestor(of: found, matching: find.byType(SingleChildScrollView))
      .last);
  expect(viewport.contains(tester.getCenter(found)), isTrue,
      reason: '$text at ${tester.getCenter(found)}, viewport $viewport');
}

Future<void> _createNewUser(WidgetTester tester) async {
  await _open(tester);
  await _fill(tester,
      name: 'new-user', email: 'new.user@example.test', password: 'secret');
  await _submit(tester);
  expect(find.byType(CreateUserDialog), findsNothing);
}

String _fieldText(WidgetTester tester, String key) => tester
    .widget<TextFormField>(find.byKey(Key(key)))
    .controller!
    .text;

void main() {
  group('validation, as the core admin dialog does it', () {
    test('email: the core pattern, found anywhere in the text', () {
      for (final ok in [
        'new.user@example.test',
        'first+tag@lab-one.example.org',
        '  padded@example.test  ',
      ]) {
        expect(validateNewUserEmail(ok), isNull, reason: ok);
      }
      for (final bad in [
        '',
        'no-at-sign.example.test',
        'user@nodot',
        'user@example.t',
        'user@example.12',
        '@example.test',
      ]) {
        expect(validateNewUserEmail(bad), 'A valid email must be supplied.',
            reason: bad);
      }
    });

    test('name and password are required', () {
      expect(validateNewUserName(''), 'A name is required.');
      expect(validateNewUserName('   '), 'A name is required.');
      expect(validateNewUserName('new-user'), isNull);
      expect(validateNewUserPassword(''), 'A password is required.');
      expect(validateNewUserPassword('invented-secret'), isNull);
    });

    testWidgets('an invalid form is not sent', (tester) async {
      final data = await _pump(tester);
      await _open(tester);
      data.client.calls.clear();

      await _submit(tester);
      expect(find.text('A name is required.'), findsOneWidget);
      expect(find.text('A valid email must be supplied.'), findsOneWidget);
      expect(find.text('A password is required.'), findsOneWidget);

      await _fill(tester,
          name: 'new-user', email: 'not-an-email', password: 'secret');
      await _submit(tester);
      expect(find.text('A name is required.'), findsNothing);
      expect(find.text('A valid email must be supplied.'), findsOneWidget);
      expect(find.text('A password is required.'), findsNothing);

      expect(data.client.calls, isEmpty);
      expect(find.byType(CreateUserDialog), findsOneWidget);
      await _unmount(tester);
    });
  });

  testWidgets('a create closes the dialog and the list shows the new user',
      (tester) async {
    final data = await _pump(tester);
    expect(find.text('new-user'), findsNothing);
    expect(find.text('Showing 3 of 3 users'), findsOneWidget);

    await _open(tester);
    data.client.calls.clear();
    await _fill(tester,
        name: 'new-user',
        email: '  new.user@example.test ',
        password: 'invented-secret');
    await _submit(tester);

    // Built as the core dialog builds it: the email trimmed.
    expect(data.client.calls, ['createUser', 'listUsers']);
    expect(data.client.created.single['name'], 'new-user');
    expect(data.client.created.single['email'], 'new.user@example.test');
    expect(data.client.created.single['isValidated'], true);
    expect(data.client.passwords.single, 'invented-secret');

    expect(find.byType(CreateUserDialog), findsNothing);
    expect(find.text('Created new-user'), findsOneWidget);
    expect(find.text('new-user'), findsOneWidget);
    expect(find.text('new.user@example.test'), findsOneWidget);
    expect(find.text('Showing 4 of 4 users'), findsOneWidget);
    // Every column is still there, the role controls included.
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
    expect(find.byTooltip('Change roles'), findsNWidgets(4));
    await _unmount(tester);
  });

  group('after a create the new row is on screen', () {
    testWidgets('from page 2, when the new user lists first', (tester) async {
      await _pump(tester, rows: _manyRows());
      await _nextPage(tester);
      expect(find.text('51–100 of 120'), findsOneWidget);

      await _createNewUser(tester);
      expect(find.text('Showing 121 of 121 users'), findsOneWidget);
      expect(find.text('1–50 of 121'), findsOneWidget);
      _expectOnScreen(tester, 'new-user');
      await _unmount(tester);
    });

    testWidgets('from page 2, when the new user lists last', (tester) async {
      final data = await _pump(tester, rows: _manyRows());
      data.client.appendCreated = true;
      await _nextPage(tester);

      await _createNewUser(tester);
      expect(find.text('101–121 of 121'), findsOneWidget);
      _expectOnScreen(tester, 'new-user');
      await _unmount(tester);
    });

    testWidgets('with a filter the new user does not match', (tester) async {
      await _pump(tester, rows: _manyRows());
      await tester.enterText(find.byType(TextField).first, 'user-07');
      await tester.pumpAndSettle();
      expect(find.text('Showing 10 of 120 users'), findsOneWidget);

      await _createNewUser(tester);
      // The filter is cleared, so the new row is not hidden by it.
      expect(find.text('Showing 121 of 121 users'), findsOneWidget);
      expect(
          tester.widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          isEmpty);
      _expectOnScreen(tester, 'new-user');
      await _unmount(tester);
    });

    testWidgets('a filter after the create starts again at the first page',
        (tester) async {
      final data = await _pump(tester, rows: _manyRows());
      data.client.appendCreated = true;
      await _createNewUser(tester);
      expect(find.text('101–121 of 121'), findsOneWidget);

      // Nine matches: without the reset the table would open at row 101,
      // past the end, and show an empty page.
      await tester.enterText(find.byType(TextField).first, 'user-00');
      await tester.pumpAndSettle();
      expect(find.text('Showing 9 of 121 users'), findsOneWidget);
      expect(find.text('1–9 of 9'), findsOneWidget);
      _expectOnScreen(tester, 'user-001');
      _expectOnScreen(tester, 'user-009');
      await _unmount(tester);
    });

    testWidgets('a later reload keeps the page the admin is on',
        (tester) async {
      await _pump(tester, rows: _manyRows());
      await _createNewUser(tester);
      await _nextPage(tester);
      expect(find.text('51–100 of 121'), findsOneWidget);

      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(find.text('51–100 of 121'), findsOneWidget);
      await _unmount(tester);
    });
  });

  testWidgets('a server error is shown and the input is kept',
      (tester) async {
    final data = await _pump(tester);
    data.client.refusal = {
      'statusCode': 400,
      'error': 'user.create.username.not.available',
      'reason': 'Username "ada" is not available.',
    };
    await _open(tester);
    data.client.calls.clear();
    await _fill(tester,
        name: 'ada', email: 'ada.two@example.test', password: 'secret');
    await _submit(tester);

    expect(data.client.calls, ['createUser']);
    expect(find.byType(CreateUserDialog), findsOneWidget);
    expect(find.byKey(const Key('create-user-error')), findsOneWidget);
    expect(find.text('Username "ada" is not available.'), findsOneWidget);
    expect(_fieldText(tester, 'create-user-name'), 'ada');
    expect(_fieldText(tester, 'create-user-email'), 'ada.two@example.test');
    expect(_fieldText(tester, 'create-user-password'), 'secret');

    // Corrected and sent again, it goes through and the error is gone.
    data.client.refusal = null;
    await tester.enterText(
        find.byKey(const Key('create-user-name')), 'ada-two');
    await _submit(tester);
    expect(find.byType(CreateUserDialog), findsNothing);
    expect(find.text('ada-two'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('cancel sends nothing', (tester) async {
    final data = await _pump(tester);
    await _open(tester);
    data.client.calls.clear();
    await _fill(tester,
        name: 'new-user', email: 'new@example.test', password: 'secret');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(CreateUserDialog), findsNothing);
    expect(data.client.calls, isEmpty);
    await _unmount(tester);
  });

  testWidgets('only an admin sees the control', (tester) async {
    await _pump(tester, session: fakeSession('grace', const ['manager']));
    expect(find.text('ada'), findsOneWidget);
    expect(find.text('Create user'), findsNothing);
    await _unmount(tester);
  });
}
