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

/// Durable per-browser preferences (theme). Unlike the session token these
/// outlive the tab, so they use localStorage.
String readSetting(String key) {
  try {
    return web.window.localStorage.getItem(key) ?? '';
  } catch (_) {
    return '';
  }
}

void writeSetting(String key, String value) {
  try {
    web.window.localStorage.setItem(key, value);
  } catch (_) {
    // Storage blocked (private mode); the choice just won't persist.
  }
}

/// Reflect view state in the URL so a panel can be linked to
/// (`?section=usage&period=lastYear`) without adding a router.
void setUrlParam(String key, String value) {
  try {
    final params = Map.of(Uri.base.queryParameters)
      ..remove('token')
      ..[key] = value;
    web.window.history.replaceState(
        null, '', Uri.base.replace(queryParameters: params).toString());
  } catch (_) {
    // Cosmetic only.
  }
}

String readUrlParam(String key) {
  try {
    return Uri.base.queryParameters[key] ?? '';
  } catch (_) {
    return '';
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

/// Open a URL in a new browser tab (workflow/project links).
void openUrl(String url) {
  try {
    web.window.open(url, '_blank');
  } catch (_) {
    // Popup blocked; nothing sensible to do.
  }
}

/// True on touch devices. Survives Chrome's "Desktop site" mode, which
/// spoofs a desktop UA and ignores the viewport meta (the page then lays
/// out at ~980px) but cannot hide the touchscreen.
bool isTouchDevice() {
  try {
    return web.window.navigator.maxTouchPoints > 0;
  } catch (_) {
    return false;
  }
}
