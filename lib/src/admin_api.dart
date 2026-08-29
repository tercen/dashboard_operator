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

  /// POST api/v1/admin/getConfigSummary — redacted server config.
  Future<Map<String, String>> getConfigSummary() async =>
      _pairs('api/v1/admin/getConfigSummary');

  /// POST api/v1/admin/getGcStatus — garbage-collector state.
  Future<Map<String, dynamic>> getGcStatus() async =>
      _jsonCall('api/v1/admin/getGcStatus', const {});

  /// POST api/v1/admin/getStorageReport — per-team storage for a domain
  /// (empty string = the caller's own domain).
  Future<Map<String, dynamic>> getStorageReport({String domain = ''}) async =>
      _jsonCall('api/v1/admin/getStorageReport', {'domain': domain});

  /// POST api/v1/admin/findActivities — cross-domain audit feed.
  Future<Map<String, dynamic>> findActivities({int limit = 100}) async =>
      _jsonCall('api/v1/admin/findActivities', {'limit': limit});

  /// POST api/v1/admin/listUsers — users across domains.
  Future<List<Map<String, dynamic>>> listUsers({int limit = 500}) async {
    final report = await _jsonCall('api/v1/admin/listUsers', {'limit': limit});
    return ((report['rows'] as List?) ?? [])
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  }

  /// POST api/v1/admin/grantRole | revokeRole — returns the new role list.
  Future<List<String>> changeRole({
    required String username,
    required String role,
    required bool grant,
  }) async {
    final response = await _post(
        'api/v1/admin/${grant ? 'grantRole' : 'revokeRole'}',
        {'username': username, 'role': role});
    final decoded = codec.decode(response.body);
    return (decoded as List).map((r) => '$r').toList();
  }

  Future<Map<String, String>> _pairs(String path) async {
    final response = await _post(path, const {});
    final pairs = (codec.decode(response.body) as List).cast<Map>();
    return {for (final pair in pairs) '${pair['key']}': '${pair['value']}'};
  }

  /// Calls an endpoint that answers with a JSON document. The TSON codec
  /// may hand it back bare, wrapped in a single-element list, or already
  /// decoded — accept all three rather than guessing.
  Future<Map<String, dynamic>> _jsonCall(
      String path, Map<String, Object> params) async {
    final response = await _post(path, params);
    var payload = codec.decode(response.body);
    if (payload is List && payload.isNotEmpty) payload = payload.first;
    if (payload is String) payload = json.decode(payload);
    if (payload is! Map) {
      throw ServiceError(
          500, 'admin.decode', 'unexpected payload ${payload.runtimeType}');
    }
    return Map<String, dynamic>.from(payload);
  }

  Future<http_api.Response> _post(
      String path, Map<String, Object> params) async {
    final response = await client.post(
        http_api.HttpClient.ResolveUri(base, path),
        headers: codec.contentTypeHeader,
        responseType: codec.responseType,
        body: codec.encode(params));
    if (response.statusCode != 200) throw _serviceError(response);
    return response;
  }

  /// Error code raised when the server predates these endpoints — the
  /// route simply does not exist, so the response is a 404 with no
  /// service-error body.
  static const unavailableCode = 'admin.service.unavailable';

  ServiceError _serviceError(http_api.Response response) {
    final status = response.statusCode ?? 0;
    if (status == 404) {
      return ServiceError(404, unavailableCode,
          'This Tercen server does not provide the dashboard API yet.');
    }
    try {
      final m = codec.decode(response.body) as Map;
      return ServiceError(status, '${m['error']}', '${m['reason']}');
    } catch (_) {
      return ServiceError(status, 'admin.api', 'HTTP $status');
    }
  }
}
