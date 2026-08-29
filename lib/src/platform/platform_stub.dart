import 'package:sci_http_client/http_client.dart' as http_api;
import 'package:sci_http_client/http_io_client.dart';

/// Non-web fallback (VM tests, tooling). The dashboard itself ships as a
/// Tercen web app; browser-only conveniences are no-ops here.
http_api.HttpClient createPlatformHttpClient() => HttpIOClient();

String readStoredToken(String key) => '';

void storeToken(String key, String value) {}

void scrubTokenFromUrl() {}

/// Durable per-browser preferences (theme). No-op off the web.
String readSetting(String key) => '';

void writeSetting(String key, String value) {}
