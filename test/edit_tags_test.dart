import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sci_http_client/content_codec.dart';
import 'package:sci_http_client/http_client.dart' as http_api;
import 'package:sci_tercen_client/sci_client.dart' as sci;

import 'package:tercen_dashboard/src/admin_api.dart';
import 'package:tercen_dashboard/src/data.dart';
import 'package:tercen_dashboard/src/screens/edit_tags_dialog.dart';
import 'package:tercen_dashboard/src/screens/users_screen.dart';
import 'package:tercen_dashboard/src/session.dart';
import 'package:tercen_dashboard/src/theme.dart';
import 'package:tercen_dashboard/src/user_document.dart';
import 'package:tercen_dashboard/src/user_filters.dart';

import 'support/fake_data.dart';

final _codec = ContentCodec.tson();
final _base = Uri.parse('https://tercen.example');

class _FakeResponse implements http_api.Response {
  @override
  final int statusCode;
  @override
  final Map? headers = const {};
  @override
  final Object? body;
  _FakeResponse(this.body, {this.statusCode = 200});
}

/// A stored user document as a newer server might hold it: every field the
/// pinned client knows about a user, and more it does not — top-level, in a
/// nested object, in a list — in an order of the server's own. Invented.
Map<String, Object?> _storedDoc({
  String id = 'user-a',
  String rev = '7-aaaa',
  List<Object?> tags = const ['pilot', 'beta'],
  String domain = '',
}) =>
    {
      'kind': 'User',
      'id': id,
      'isDeleted': false,
      'rev': rev,
      'name': id,
      'email': '$id@example.test',
      'fieldUnknownToTheClient': 'keep me',
      'isValidated': true,
      'domain': domain,
      'roles': ['user'],
      'tags': tags,
      'futureSettings': {
        'kind': 'FutureSettings',
        'nested': [1, 2.5, true, 'x', null],
        'deeper': {'a': 'b'},
      },
      'createdDate': {'kind': 'Date', 'value': '2026-09-01T12:00:00'},
      'meta': [
        {'kind': 'Pair', 'key': 'invented.key', 'value': 'invented value'},
      ],
      'aNumberTheClientDropsToo': 42,
    };

/// The user endpoints as a server holds them: GET answers the stored
/// document, POST stores the document it is sent when its rev is the stored
/// one and answers the new rev, and refuses it with a 409 otherwise.
/// [changeBeforeNextPost] has someone else change the user first, as happens
/// between the read and the save; [refuseNextPost] refuses the next save
/// with that status. listUsers lists the stored documents of every domain;
/// listUserActivity is missing (404).
///
/// [docs] are the documents of the session's [domain], [elsewhere] the
/// other domains', which are listed only.
class _UserServer implements http_api.HttpClient {
  final String domain;
  final Map<String, Map<String, Object?>> docs;
  final List<Map<String, Object?>> elsewhere;
  final List<String> calls = [];
  final List<Object?> postedBodies = [];
  Map<String, Object?>? changeBeforeNextPost;
  int? refuseNextPost;
  _UserServer(List<Map<String, Object?>> docs, {this.domain = ''})
      : docs = {
          for (final d in docs)
            if (d['domain'] == domain) '${d['id']}': d,
        },
        elsewhere = [
          for (final d in docs)
            if (d['domain'] != domain) d,
        ];

  @override
  Future<http_api.Response> get(url,
      {Map<String, String>? headers, String? responseType}) async {
    final uri = Uri.parse('$url');
    expect(uri.path, '/api/v1/user');
    final id = uri.queryParameters['id']!;
    calls.add('get $id');
    return _FakeResponse(_codec.encode(docs[id]));
  }

  @override
  Future<http_api.Response> post(url,
      {Map<String, String>? headers,
      body,
      String? responseType,
      encoding,
      progressCallback}) async {
    final uri = Uri.parse('$url');
    if (uri.path == '/api/v1/user') {
      postedBodies.add(body);
      final sent = Map<String, Object?>.from(_codec.decode(body) as Map);
      final id = '${sent['id']}';
      calls.add('update $id');
      final refuse = refuseNextPost;
      if (refuse != null) {
        refuseNextPost = null;
        return _FakeResponse(
            _codec.encode({
              'statusCode': refuse,
              'error': 'user.update.refused',
              'reason': 'invented refusal',
            }),
            statusCode: refuse);
      }
      final change = changeBeforeNextPost;
      if (change != null) {
        docs[id] = change;
        changeBeforeNextPost = null;
      }
      final stored = docs[id]!;
      if (sent['rev'] != stored['rev']) {
        return _FakeResponse(
            _codec.encode({
              'statusCode': 409,
              'error': 'user.update.conflict',
              'reason': 'invented conflict',
            }),
            statusCode: 409);
      }
      final number = int.parse('${stored['rev']}'.split('-').first) + 1;
      final rev = '$number-bbbb';
      docs[id] = {...sent, 'rev': rev};
      return _FakeResponse(_codec.encode([rev]));
    }
    final endpoint = uri.pathSegments.last;
    calls.add(endpoint);
    if (endpoint == 'listUserActivity') {
      return _FakeResponse('', statusCode: 404);
    }
    final rows = [
      for (final d in [...docs.values, ...elsewhere])
        {
          'id': d['id'],
          'name': d['name'],
          'email': d['email'],
          'domain': d['domain'],
          'roles': d['roles'],
          'isValidated': d['isValidated'],
          'createdDate': '2026-09-01T12:00:00',
          'tags': d['tags'],
          'projectsOwned': 0,
        },
    ];
    return _FakeResponse(_codec.encode(json.encode(
        {'rows': rows, 'total': rows.length, 'truncated': false})));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// The real [DashboardData] over [server], signed in as [session].
class _ServerData extends DashboardData {
  final _UserServer server;
  _ServerData(this.server, DashboardSession session)
      : super(session..serviceBase = _base, settings: MemorySettings());

  @override
  AdminApi get adminApi => AdminApi(_base, server);

  @override
  UserDocumentApi get userDocumentApi => UserDocumentApi(_base, server);
}

Future<_UserServer> _pump(WidgetTester tester, List<Map<String, Object?>> docs,
    {DashboardSession? session}) async {
  session ??= fakeAdminSession();
  final server = _UserServer(docs, domain: session.domain);
  final data = _ServerData(server, session);
  tester.view
    ..physicalSize = const Size(1728, 1200)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: DashboardTheme.light,
    home: Scaffold(body: UsersScreen(data: data)),
  ));
  await tester.pumpAndSettle();
  return server;
}

Future<void> _open(WidgetTester tester, String id,
    {String domain = ''}) async {
  await tester.tap(find.byKey(Key('edit-tags-$domain-$id')));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('edit-tags-field')), text);
  await tester.tap(find.byKey(const Key('edit-tags-add')));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('edit-tags-save')));
  await tester.pumpAndSettle();
}

/// The chips in the dialog, left to right.
List<String> _chips(WidgetTester tester) => [
      for (final chip in tester.widgetList<InputChip>(find.descendant(
          of: find.byType(EditTagsDialog), matching: find.byType(InputChip))))
        (chip.label as Text).data!,
    ];

/// The one document the page stored, decoded.
Map<String, Object?> _posted(_UserServer server) {
  expect(server.postedBodies, hasLength(1));
  return Map<String, Object?>.from(
      _codec.decode(server.postedBodies.single) as Map);
}

/// The panel refreshes on a timer; unmount so it does not outlive the test.
Future<void> _unmount(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox());

void main() {
  group('the raw round trip', () {
    test('a tag edit sends back the stored document, byte for byte, but tags',
        () async {
      final stored = _storedDoc();
      final server = _UserServer([stored]);
      final api = UserDocumentApi(_base, server);

      final document = await api.get('user-a');
      final rev = await api
          .update(document.withTagEdit(removed: {'beta'}, added: ['gamma']));

      expect(rev, '8-bbbb');
      expect(server.calls, ['get user-a', 'update user-a']);
      // What went out is the stored document, keys in their stored order,
      // with only tags replaced — the very bytes of encoding that.
      final expected = {...stored, 'tags': ['pilot', 'gamma']};
      expect(server.postedBodies.single, _codec.encode(expected));
      final sent = Map<String, Object?>.from(
          _codec.decode(server.postedBodies.single) as Map);
      expect(sent.keys.toList(), stored.keys.toList());
      for (final key in stored.keys) {
        if (key == 'tags') continue;
        expect(sent[key], stored[key], reason: key);
      }
      expect(sent['tags'], ['pilot', 'gamma']);
    });

    test('the typed model would have dropped the unknown fields', () {
      // Why the round trip is raw: the pinned client's User, read and
      // written back, loses what it does not know.
      final typed = sci.User.json(_storedDoc()).toJson();
      expect(typed.containsKey('fieldUnknownToTheClient'), isFalse);
      expect(typed.containsKey('futureSettings'), isFalse);
      expect(typed.containsKey('aNumberTheClientDropsToo'), isFalse);
    });

    test('a conflict is raised as a 409, not retried', () async {
      final server = _UserServer([_storedDoc()]);
      final api = UserDocumentApi(_base, server);
      final document = await api.get('user-a');
      server.changeBeforeNextPost = _storedDoc(rev: '8-cccc');

      await expectLater(
          api.update(document.withTagEdit(added: ['gamma'])),
          throwsA(predicate((e) => '$e'.contains('409'))));
      expect(server.calls, ['get user-a', 'update user-a']);
    });

    test('withTagEdit leaves a stored entry it does not show where it is', () {
      final document = UserDocument(
          _storedDoc(tags: ['pilot', null, '', 7, 'pilot', 'beta']));
      expect(document.tags, ['pilot', 'beta']);
      expect(document.withTagEdit(removed: {'pilot'}, added: ['gamma'])
          .json['tags'], [null, '', 7, 'beta', 'gamma']);
      // Nothing asked, nothing changed.
      expect(document.withTagEdit().json, document.json);
    });

    test('checkNewTag trims, and refuses empty and duplicate tags', () {
      expect(checkNewTag('  gamma ', ['pilot']), (tag: 'gamma', problem: null));
      expect(checkNewTag('   ', ['pilot']),
          (tag: null, problem: 'A tag cannot be empty'));
      expect(checkNewTag('', []),
          (tag: null, problem: 'A tag cannot be empty'));
      expect(checkNewTag(' pilot', ['pilot']),
          (tag: null, problem: '"pilot" is already a tag'));
      // Tags are compared as stored: another case is another tag.
      expect(checkNewTag('Pilot', ['pilot']), (tag: 'Pilot', problem: null));
    });
  });

  group('the Tags cell editor', () {
    testWidgets('add: the tag is saved and the list reloads', (tester) async {
      final server = await _pump(tester, [_storedDoc()]);
      expect(server.calls.where((c) => c == 'listUsers'), hasLength(1));

      await _open(tester, 'user-a');
      expect(_chips(tester), ['pilot', 'beta']);
      await _type(tester, '  gamma  ');
      expect(_chips(tester), ['pilot', 'beta', 'gamma']);
      await _save(tester);

      final sent = _posted(server);
      expect(sent['tags'], ['pilot', 'beta', 'gamma']);
      expect(sent['fieldUnknownToTheClient'], 'keep me');
      expect(sent['rev'], '7-aaaa');
      expect(find.byType(EditTagsDialog), findsNothing);
      expect(find.text('Saved the tags of user-a'), findsOneWidget);
      // The list is read again, and shows the new tag (the cell's tooltip
      // holds the full list).
      expect(server.calls.where((c) => c == 'listUsers'), hasLength(2));
      expect(find.byTooltip('pilot, beta, gamma'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('remove: the chip goes, the rest of the document stays',
        (tester) async {
      final stored = _storedDoc();
      final server = await _pump(tester, [stored]);

      await _open(tester, 'user-a');
      await tester.tap(find.byTooltip('Remove pilot'));
      await tester.pumpAndSettle();
      expect(_chips(tester), ['beta']);
      await _save(tester);

      final sent = _posted(server);
      expect(sent, {...stored, 'tags': ['beta']});
      expect(find.byTooltip('beta'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('removing every tag stores an empty list', (tester) async {
      final server = await _pump(tester, [_storedDoc()]);

      await _open(tester, 'user-a');
      await tester.tap(find.byTooltip('Remove pilot'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove beta'));
      await tester.pumpAndSettle();
      expect(find.text('No tags'), findsOneWidget);
      await _save(tester);

      expect(_posted(server)['tags'], isEmpty);
      await _unmount(tester);
    });

    testWidgets('a duplicate is refused, and a stored duplicate is one chip',
        (tester) async {
      final server = await _pump(
          tester, [_storedDoc(tags: ['pilot', 'beta', 'pilot'])]);

      await _open(tester, 'user-a');
      expect(_chips(tester), ['pilot', 'beta']);
      await _type(tester, ' pilot ');
      expect(find.text('"pilot" is already a tag'), findsOneWidget);
      expect(_chips(tester), ['pilot', 'beta']);

      // One just added cannot be added twice either.
      await _type(tester, 'gamma');
      expect(find.text('"pilot" is already a tag'), findsNothing);
      await _type(tester, 'gamma');
      expect(find.text('"gamma" is already a tag'), findsOneWidget);
      expect(_chips(tester), ['pilot', 'beta', 'gamma']);

      // Removing the stored duplicate removes it wherever it is stored.
      await tester.tap(find.byTooltip('Remove pilot'));
      await tester.pumpAndSettle();
      await _save(tester);
      expect(_posted(server)['tags'], ['beta', 'gamma']);
      await _unmount(tester);
    });

    testWidgets('an empty tag is refused; empty stored entries are kept',
        (tester) async {
      final server =
          await _pump(tester, [_storedDoc(tags: ['pilot', '', 'beta'])]);

      await _open(tester, 'user-a');
      expect(_chips(tester), ['pilot', 'beta']);
      await _type(tester, '');
      expect(find.text('A tag cannot be empty'), findsOneWidget);
      await _type(tester, '    ');
      expect(find.text('A tag cannot be empty'), findsOneWidget);
      expect(_chips(tester), ['pilot', 'beta']);

      await _type(tester, 'gamma');
      await _save(tester);
      // The stored '' is not this page's to remove: it stays where it was.
      expect(_posted(server)['tags'], ['pilot', '', 'beta', 'gamma']);
      await _unmount(tester);
    });

    testWidgets('saving with nothing changed sends nothing', (tester) async {
      final server = await _pump(tester, [_storedDoc()]);

      await _open(tester, 'user-a');
      await _type(tester, 'gamma');
      await tester.tap(find.byTooltip('Remove gamma'));
      await tester.pumpAndSettle();
      await _save(tester);

      expect(server.postedBodies, isEmpty);
      expect(find.byType(EditTagsDialog), findsNothing);
      expect(server.calls.where((c) => c == 'listUsers'), hasLength(1));
      await _unmount(tester);
    });

    testWidgets('a conflict shows an error and reloads, and is not retried',
        (tester) async {
      final server = await _pump(tester, [_storedDoc()]);

      await _open(tester, 'user-a');
      await _type(tester, 'gamma');
      // Someone else tags the user between the read and the save.
      server.changeBeforeNextPost =
          _storedDoc(rev: '8-cccc', tags: ['pilot', 'beta', 'theirs']);
      await _save(tester);

      // One save, refused; then the user read again — never a second save.
      expect(server.calls.where((c) => c.startsWith('update')), hasLength(1));
      expect(server.calls.where((c) => c == 'get user-a'), hasLength(2));
      expect(find.byType(EditTagsDialog), findsOneWidget);
      expect(find.byKey(const Key('edit-tags-error')), findsOneWidget);
      expect(find.text(EditTagsDialog.conflictMessage), findsOneWidget);
      // The tags as they now are; the edit is dropped, not re-applied.
      expect(_chips(tester), ['pilot', 'beta', 'theirs']);
      expect(server.docs['user-a']!['tags'], ['pilot', 'beta', 'theirs']);

      // Made again, the change is saved under the new rev.
      await _type(tester, 'gamma');
      await _save(tester);
      expect(server.calls.where((c) => c.startsWith('update')), hasLength(2));
      final second = Map<String, Object?>.from(
          _codec.decode(server.postedBodies.last) as Map);
      expect(second['rev'], '8-cccc');
      expect(second['tags'], ['pilot', 'beta', 'theirs', 'gamma']);
      expect(find.byType(EditTagsDialog), findsNothing);
      await _unmount(tester);
    });

    testWidgets('another server error is shown and the edit kept',
        (tester) async {
      final server = await _pump(tester, [_storedDoc()]);
      await _open(tester, 'user-a');
      await _type(tester, 'gamma');
      server.refuseNextPost = 403;
      await _save(tester);

      expect(find.byType(EditTagsDialog), findsOneWidget);
      expect(find.text('invented refusal'), findsOneWidget);
      // Not a conflict: nothing read again, the edit still there.
      expect(server.calls.where((c) => c == 'get user-a'), hasLength(1));
      expect(_chips(tester), ['pilot', 'beta', 'gamma']);
      expect(server.docs['user-a']!['tags'], ['pilot', 'beta']);
      await _unmount(tester);
    });

    testWidgets('admins get the control on every row of their domain',
        (tester) async {
      await _pump(tester, [_storedDoc(), _storedDoc(id: 'user-b')]);
      expect(find.byTooltip('Edit tags'), findsNWidgets(2));
      await _unmount(tester);
    });

    // Tag and role controls act on the admin's own domain, so they are
    // shown only on its rows.
    testWidgets('two domains listed: only the own-domain row edits',
        (tester) async {
      final own = _storedDoc(id: 'user-a', tags: ['ours']);
      final other =
          _storedDoc(id: 'user-a', domain: 'north', tags: ['theirs']);
      final server = await _pump(tester, [own, other]);

      // Both rows are listed; only the default domain's has the control.
      expect(find.byTooltip('ours'), findsOneWidget);
      expect(find.byTooltip('theirs'), findsOneWidget);
      expect(find.byKey(const Key('edit-tags--user-a')), findsOneWidget);
      expect(find.byKey(const Key('edit-tags-north-user-a')), findsNothing);
      expect(find.byTooltip('Edit tags'), findsOneWidget);

      // The own row edits its own document, and only that one.
      await _open(tester, 'user-a');
      expect(_chips(tester), ['ours']);
      await _type(tester, 'gamma');
      await _save(tester);
      expect(_posted(server)['tags'], ['ours', 'gamma']);
      expect(server.docs['user-a']!['tags'], ['ours', 'gamma']);
      expect(server.elsewhere.single['tags'], ['theirs']);
      await _unmount(tester);
    });

    testWidgets('an admin of another domain edits only that domain\'s rows',
        (tester) async {
      final server = await _pump(tester, [
        _storedDoc(id: 'user-a', tags: ['default-tag']),
        _storedDoc(id: 'user-a', domain: 'north', tags: ['north-tag']),
      ], session: fakeAdminSession()..domain = 'north');

      expect(find.byKey(const Key('edit-tags--user-a')), findsNothing);
      expect(find.byTooltip('Edit tags'), findsOneWidget);
      await _open(tester, 'user-a', domain: 'north');
      expect(_chips(tester), ['north-tag']);
      await _type(tester, 'gamma');
      await _save(tester);
      expect(server.docs['user-a']!['tags'], ['north-tag', 'gamma']);
      expect(server.elsewhere.single['tags'], ['default-tag']);
      await _unmount(tester);
    });

    testWidgets('the control is hidden for a non-admin', (tester) async {
      await _pump(tester, [_storedDoc(), _storedDoc(id: 'user-b')],
          session: fakeSession('invented-manager', ['manager']));
      expect(find.byTooltip('Edit tags'), findsNothing);
      expect(find.byType(IconButton).evaluate().where((e) =>
          (e.widget as IconButton).tooltip == 'Edit tags'), isEmpty);
      // The tags are still shown, read-only.
      expect(find.byTooltip('pilot, beta'), findsNWidgets(2));
      await _unmount(tester);
    });
  });
}
