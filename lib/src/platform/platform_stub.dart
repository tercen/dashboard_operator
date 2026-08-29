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

void setUrlParam(String key, String value) {}

String readUrlParam(String key) => '';

/// Open a URL in a new browser tab (workflow/project links). No-op off web.
void openUrl(String url) {}

/// True on touch devices. Off the web there is no such signal.
bool isTouchDevice() => false;
