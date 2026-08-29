import 'package:sci_http_client/http_browser_client.dart';
import 'package:sci_http_client/http_client.dart' as http_api;
import 'package:web/web.dart' as web;

http_api.HttpClient createPlatformHttpClient() => HttpBrowserClient();

String readStoredToken(String key) {
  try {
    return web.window.sessionStorage.getItem(key) ?? '';
  } catch (_) {
    return '';
  }
}

void storeToken(String key, String value) {
  try {
    web.window.sessionStorage.setItem(key, value);
  } catch (_) {
    // Storage unavailable (private mode); the in-memory token still works
    // for the lifetime of the page.
  }
}

void scrubTokenFromUrl() {
  try {
    final params = Map.of(Uri.base.queryParameters)..remove('token');
    final cleaned =
        Uri.base.replace(queryParameters: params.isEmpty ? null : params);
    web.window.history.replaceState(null, '', cleaned.toString());
  } catch (_) {
    // Cosmetic only; failing to scrub must not break the session.
  }
}
