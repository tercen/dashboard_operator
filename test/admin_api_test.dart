import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sci_http_client/content_codec.dart';
import 'package:sci_http_client/error.dart';
import 'package:sci_http_client/http_client.dart' as http_api;

import 'package:tercen_dashboard/src/admin_api.dart';
import 'package:tercen_dashboard/src/data.dart';
import 'package:tercen_dashboard/src/user_activity.dart';

class _FakeResponse implements http_api.Response {
  @override
  final int statusCode;
  @override
  final Map? headers = const {};
  @override
  final Object? body;
  _FakeResponse(this.statusCode, this.body);
}

class _FakeClient implements http_api.HttpClient {
  final _FakeResponse response;
  Uri? lastUri;
  Object? lastBody;
  _FakeClient(this.response);

  @override
  Future<http_api.Response> post(url,
      {Map<String, String>? headers,
      body,
      String? responseType,
      encoding,
      progressCallback}) async {
    lastUri = url is Uri ? url : Uri.parse('$url');
    lastBody = body;
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  final codec = ContentCodec.tson();
  final base = Uri.parse('https://tercen.example');

  List<Map<String, String>> pairs(Map<String, String> values) => [
        for (final e in values.entries)
          {'kind': 'Pair', 'key': e.key, 'value': e.value}
      ];

  test('getSchedulerStatus decodes the pair list', () async {
    final encoded = codec.encode(pairs({
      'isLeader': 'true',
      'isRunning': 'true',
      'totalWorkers': '3',
      'availableWorkers': '1',
      'busyWorkers': '2',
      'queueSize': '5',
      'schedulerVersion': '0.34.8',
    }));
    final client = _FakeClient(_FakeResponse(200, encoded));

    final api = AdminApi(base, client);
    final status = SchedulerStatus(await api.getSchedulerStatus());

    expect(client.lastUri.toString(),
        'https://tercen.example/api/v1/admin/getSchedulerStatus');
    expect(status.isLeader, isTrue);
    expect(status.isRunning, isTrue);
    expect(status.totalWorkers, 3);
    expect(status.availableWorkers, 1);
    expect(status.busyWorkers, 2);
    expect(status.queueSize, 5);
    expect(status.schedulerVersion, '0.34.8');
  });

  test('non-200 becomes a ServiceError with the server code', () async {
    final encoded = codec.encode({
      'error': 'admin.service.get.scheduler.status',
      'reason': 'forbidden',
    });
    final client = _FakeClient(_FakeResponse(403, encoded));

    final api = AdminApi(base, client);

    await expectLater(
      api.getSchedulerStatus(),
      throwsA(isA<ServiceError>().having((e) => e.statusCode, 'statusCode', 403)),
    );
  });

  group('listUsers', () {
    // Invented users. The service answers with a JSON document as a string.
    Map<String, Object?> row(String name, Object? createdDate) => {
          'id': 'user-$name',
          'name': name,
          'email': '$name@example.test',
          'domain': '',
          'roles': ['user'],
          'isValidated': true,
          'createdDate': createdDate,
        };

    Future<(UserRows, _FakeClient)> call(Map<String, Object?> report) async {
      final client =
          _FakeClient(_FakeResponse(200, codec.encode(json.encode(report))));
      return (await AdminApi(base, client).listUsers(), client);
    }

    test('asks for the server maximum of 1000', () async {
      final (_, client) = await call({'rows': []});
      expect(client.lastUri.toString(),
          'https://tercen.example/api/v1/admin/listUsers');
      expect((codec.decode(client.lastBody) as Map)['limit'], 1000);
    });

    test('new shape: reads total and truncated, and a null createdDate',
        () async {
      final (answer, _) = await call({
        'rows': [row('ada', '2026-02-03T10:30:00.000Z'), row('grace', null)],
        'total': 1840,
        'truncated': true,
      });
      expect(answer.rows, hasLength(2));
      expect(answer.total, 1840);
      expect(answer.truncated, isTrue);

      final users = answer.rows.map(DashboardUser.fromJson).toList();
      expect(users[0].createdDate, '2026-02-03T10:30:00.000Z');
      expect(users[1].createdDate, '');
      expect(formatDate(users[1].createdDate), '—');
    });

    test('old shape: rows only, total and truncated absent', () async {
      final (answer, _) = await call({
        'rows': [row('ada', '2026-02-03T10:30:00.000Z')],
      });
      expect(answer.rows, hasLength(1));
      expect(answer.total, isNull);
      expect(answer.truncated, isNull);
    });
  });

  group('listUserActivity', () {
    test('posts the window and budget to the admin route', () async {
      // The shelf wraps the service's JSON string in a one-element list.
      final client = _FakeClient(_FakeResponse(
          200,
          codec.encode([
            json.encode({
              'budget': 20000,
              'window': {'from': '2026-08-01', 'to': '2026-08-31'},
              'rows': [
                {
                  'id': 'user-ada',
                  'name': 'ada',
                  'domain': '',
                  'activeDays': 9,
                  'activeDaysInWindow': 2,
                  'recent': [],
                  'truncated': false,
                  'windowTruncated': false,
                },
              ],
            })
          ])));
      final answer = UserActivityReport.fromJson(await AdminApi(base, client)
          .listUserActivity(from: '2026-08-01', to: '2026-08-31'));

      expect(client.lastUri.toString(),
          'https://tercen.example/api/v1/admin/listUserActivity');
      expect(codec.decode(client.lastBody),
          {'from': '2026-08-01', 'to': '2026-08-31', 'budget': 0});
      expect(answer.window, const ActivityWindow('2026-08-01', '2026-08-31'));
      expect(answer.budget, 20000);
      expect(answer[('', 'user-ada')]?.activeDaysInWindow, 2);
    });

    test('a server without the route: 404, raised as unavailable', () async {
      final client = _FakeClient(_FakeResponse(404, ''));
      await expectLater(
        AdminApi(base, client).listUserActivity(),
        throwsA(isA<ServiceError>()
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.error, 'error', AdminApi.unavailableCode)),
      );
    });
  });
}
