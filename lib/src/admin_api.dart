import 'package:sci_http_client/content_codec.dart';
import 'package:sci_http_client/error.dart';
import 'package:sci_http_client/http_client.dart' as http_api;

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
