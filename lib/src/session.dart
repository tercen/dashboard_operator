import 'dart:convert';

import 'package:sci_http_client/http_auth_client.dart' as auth_http;
import 'package:sci_http_client/http_client.dart' as http_api;
import 'package:sci_tercen_client/sci_client.dart' as sci;
import 'package:sci_tercen_client/sci_client_service_factory.dart' as tercen;

import 'platform/platform_stub.dart'
    if (dart.library.js_interop) 'platform/platform_web.dart' as platform;

/// Authenticated dashboard session.
///
/// Token resolution order:
///  1. `--dart-define=TERCEN_TOKEN=...` (local development)
///  2. the `?token=` query parameter set by Tercen's "Run App" launcher —
///     immediately moved to sessionStorage and scrubbed from the URL so it
///     doesn't linger in history or get copy-pasted with deep links
///  3. sessionStorage (page reloads within the same tab)
class DashboardSession {
  static const _storageKey = 'tercen.dashboard.token';

  bool get isDev =>
      const String.fromEnvironment('DEV', defaultValue: 'false') == 'true';
  String get devServiceUri => const String.fromEnvironment('TERCEN_URL',
      defaultValue: 'http://127.0.0.1:5400');

  late final sci.ServiceFactory factory;

  /// The authenticated HTTP client and service base URI, for API calls that
  /// are newer than the pinned client release (see AdminApi).
  late final http_api.HttpClient httpClient;
  late final Uri serviceBase;

  String token = '';
  String username = '';
  String domain = '';
  sci.User user = sci.User();

  bool get isAdmin => username == 'admin' || user.roles.contains('admin');
  bool get isManager => isAdmin || user.roles.contains('manager');

  Future<void> initialize() async {
    token = _resolveToken();
    if (token.isEmpty) {
      throw const SessionError(
          'No Tercen session token. Open the dashboard from Tercen ("Run App"), '
          'or pass --dart-define=TERCEN_TOKEN for local development.');
    }

    final claims = _decodeJwtData(token);
    username = (claims['u'] ?? '') as String;
    domain = (claims['d'] ?? '') as String;
    if (username.isEmpty) {
      throw const SessionError('Session token carries no username.');
    }

    await _initFactory();

    user = await factory.userService.get(username);
  }

  Future<void> _initFactory() async {
    final authClient = auth_http.HttpAuthClient(
        token, platform.createPlatformHttpClient());

    factory = sci.ServiceFactory();
    final base = isDev ? Uri.parse(devServiceUri) : Uri.base;
    serviceBase = Uri(scheme: base.scheme, host: base.host, port: base.port);
    httpClient = authClient;
    await factory.initializeWith(serviceBase, authClient);

    http_api.HttpClient.setCurrent(authClient);
    tercen.ServiceFactory.CURRENT = factory;
  }

  String _resolveToken() {
    const fromEnv = String.fromEnvironment('TERCEN_TOKEN');
    if (fromEnv.isNotEmpty) return fromEnv;

    final fromQuery = Uri.base.queryParameters['token'] ?? '';
    if (fromQuery.isNotEmpty) {
      platform.storeToken(_storageKey, fromQuery);
      platform.scrubTokenFromUrl();
      return fromQuery;
    }

    return platform.readStoredToken(_storageKey);
  }

  Map<String, dynamic> _decodeJwtData(String jwt) {
    final parts = jwt.split('.');
    if (parts.length != 3) {
      throw const SessionError('Malformed session token.');
    }
    final payload =
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
    final decoded = json.decode(payload) as Map<String, dynamic>;
    return (decoded['data'] ?? decoded) as Map<String, dynamic>;
  }
}

class SessionError implements Exception {
  final String message;
  const SessionError(this.message);

  @override
  String toString() => message;
}
