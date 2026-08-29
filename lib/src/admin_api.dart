import 'dart:convert';

import 'package:sci_http_client/content_codec.dart';
import 'package:sci_http_client/error.dart';
import 'package:sci_http_client/http_client.dart' as http_api;

import 'usage.dart';

/// Client for `api/v1/admin` endpoints that are newer than the pinned
/// sci_tercen_client release. Delete once the released client ships
/// `factory.adminService` and switch call sites to it.
class AdminApi {
  final Uri base;
  final http_api.HttpClient client;
  final ContentCodec codec;

  AdminApi(this.base, this.client, {ContentCodec? codec})
      : codec = codec ?? ContentCodec.tson();

  /// POST api/v1/admin/getSchedulerStatus — admin only (403 otherwise).
  ///
  /// Returns the scheduler snapshot as a key/value map: isLeader, isRunning,
  /// totalWorkers, availableWorkers, busyWorkers, queueSize, schedulerVersion.
  Future<Map<String, String>> getSchedulerStatus() async {
    final uri = http_api.HttpClient.ResolveUri(
        base, 'api/v1/admin/getSchedulerStatus');
    final response = await client.post(uri,
        headers: codec.contentTypeHeader,
        responseType: codec.responseType,
        body: codec.encode(<String, Object>{}));

    if (response.statusCode != 200) {
      throw _serviceError(response);
    }

    final pairs = (codec.decode(response.body) as List).cast<Map>();
    return {for (final pair in pairs) '${pair['key']}': '${pair['value']}'};
  }

  /// POST api/v1/usage/getUsageReport — manager or admin.
  ///
  /// [scope] is `team` or `user`; [from]/[to] are inclusive YYYY-MM-DD days;
  /// [bucket] is day | week | month | total.
  Future<UsageReport> getUsageReport({
    required String scope,
    required String from,
    required String to,
    required String bucket,
  }) async {
    final uri =
        http_api.HttpClient.ResolveUri(base, 'api/v1/usage/getUsageReport');
    final response = await client.post(uri,
        headers: codec.contentTypeHeader,
        responseType: codec.responseType,
        body: codec.encode(<String, Object>{
          'scope': scope,
          'from': from,
          'to': to,
          'bucket': bucket,
        }));

    if (response.statusCode != 200) {
      throw _serviceError(response);
    }

    // The service returns a JSON document as a string, but the TSON codec
    // may hand it back bare, wrapped in a single-element list, or already
    // decoded — accept all three rather than guessing.
    var payload = codec.decode(response.body);
    if (payload is List && payload.isNotEmpty) payload = payload.first;
    if (payload is String) payload = json.decode(payload);
    if (payload is! Map) {
      throw ServiceError(500, 'usage.report.decode',
          'unexpected payload ${payload.runtimeType}');
    }
    return UsageReport.fromJson(Map<String, dynamic>.from(payload));
  }

  ServiceError _serviceError(http_api.Response response) {
    final status = response.statusCode ?? 0;
    try {
      final m = codec.decode(response.body) as Map;
      return ServiceError(status, '${m['error']}', '${m['reason']}');
    } catch (_) {
      return ServiceError(status, 'admin.api', 'HTTP $status');
    }
  }
}
