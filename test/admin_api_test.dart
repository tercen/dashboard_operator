import 'package:flutter_test/flutter_test.dart';
import 'package:sci_http_client/content_codec.dart';
import 'package:sci_http_client/error.dart';
import 'package:sci_http_client/http_client.dart' as http_api;

import 'package:tercen_dashboard/src/admin_api.dart';
import 'package:tercen_dashboard/src/data.dart';

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
  _FakeClient(this.response);

  @override
  Future<http_api.Response> post(url,
      {Map<String, String>? headers,
      body,
      String? responseType,
      encoding,
      progressCallback}) async {
    lastUri = url is Uri ? url : Uri.parse('$url');
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
}
