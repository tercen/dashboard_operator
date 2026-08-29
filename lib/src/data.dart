import 'dart:convert';

import 'package:sci_http_client/error.dart';
import 'package:sci_tercen_client/sci_client.dart' as sci;

import 'admin_api.dart';
import 'session.dart';
import 'usage.dart';

/// Data access for the dashboard panels, on top of the existing API surface.
/// Server-side authorization is the boundary: every call here is made with the
/// session token and fails with 403 for callers without the required role.
class DashboardData {
  final DashboardSession session;
  late final AdminApi adminApi =
      AdminApi(session.serviceBase, session.httpClient);

  DashboardData(this.session);

  sci.ServiceFactory get _f => session.factory;

  /// Scheduler snapshot from AdminService (leader, worker counts, queue
  /// depth, scheduler version). Admin only.
  Future<SchedulerStatus> schedulerStatus() async =>
      SchedulerStatus(await adminApi.getSchedulerStatus());

  /// Redacted server configuration (admin only).
  Future<Map<String, String>> configSummary() => adminApi.getConfigSummary();

  /// Garbage-collector state (admin only).
  Future<Map<String, dynamic>> gcStatus() => adminApi.getGcStatus();

  /// Per-team storage for the caller's domain (admin only).
  Future<Map<String, dynamic>> storageReport() => adminApi.getStorageReport();

  /// Cross-domain activity feed (admin only).
  Future<Map<String, dynamic>> activities({int limit = 100}) =>
      adminApi.findActivities(limit: limit);

  /// Grant or revoke a role (admin only). Returns the user's new roles.
  Future<List<String>> changeRole(
          {required String username,
          required String role,
          required bool grant}) =>
      adminApi.changeRole(username: username, role: role, grant: grant);

  /// Usage rollup for the manager views. Manager or admin; the server
  /// scopes non-admin callers to their own domain.
  Future<UsageReport> usageReport({
    required String scope,
    required String from,
    required String to,
    required String bucket,
  }) =>
      adminApi.getUsageReport(
          scope: scope, from: from, to: to, bucket: bucket);

  Future<sci.Version> tercenVersion() =>
      _f.userService.getServerVersion('tercen');

  Future<sci.Version> sarnoVersion() =>
      _f.userService.getServerVersion('sarno');

  /// Live task set known to the scheduler. Admin sees all tenants.
  Future<List<sci.Task>> tasks() => _f.taskService.getTasks([]);

  /// Registered workers. (Admin-gating is a pending server-side hardening.)
  Future<List<sci.Worker>> workers() => _f.taskService.getWorkers([]);

  Future<void> cancelTask(String taskId) => _f.taskService.cancelTask(taskId);

  /// Users across domains, via AdminService — the legacy
  /// findUserByCreatedDateAndName view returns nothing on some instances.
  ///
  /// Falls back to that released query when the server has no AdminService,
  /// so this panel still works against an older Tercen (where it is the
  /// only option, empty or not).
  Future<UserListing> users({int limit = 500}) async {
    try {
      final rows = await adminApi.listUsers(limit: limit);
      return UserListing(
          users: rows.map(DashboardUser.fromJson).toList(), viaFallback: false);
    } on ServiceError catch (e) {
      if (e.statusCode != 404) rethrow;
      final legacy = await _f.userService
          .findUserByCreatedDateAndName(limit: limit, descending: true);
      return UserListing(
        users: legacy
            .where((u) => u.kind == 'User')
            .map((u) => DashboardUser(
                  id: u.id,
                  name: u.name,
                  email: u.email,
                  domain: u.domain,
                  roles: u.roles.toList(),
                  isValidated: u.isValidated,
                  createdDate: u.createdDate.value,
                ))
            .toList(),
        viaFallback: true,
      );
    }
  }

  Future<sci.ResourceSummary> userResourceSummary(String userId) =>
      _f.userService.resourceSummary(userId);

  /// Reads a task's stdout/stderr log file, capped so a runaway log cannot
  /// freeze the tab.
  Future<String> readLog(String fileDocumentId, {int maxBytes = 262144}) async {
    final chunks = <int>[];
    await for (final chunk in _f.fileService.download(fileDocumentId)) {
      chunks.addAll(chunk);
      if (chunks.length >= maxBytes) break;
    }
    final text = utf8.decode(chunks.take(maxBytes).toList(),
        allowMalformed: true);
    return chunks.length >= maxBytes
        ? '$text\n… truncated at ${maxBytes ~/ 1024} KiB'
        : text;
  }
}

/// The user list plus how it was obtained: on a server without
/// AdminService the panel falls back to findUserByCreatedDateAndName,
/// which returns nothing on some instances — an empty list then means
/// "the old query found none", not "there are no users".
class UserListing {
  final List<DashboardUser> users;
  final bool viaFallback;
  const UserListing({required this.users, required this.viaFallback});
}

/// A user row from AdminService.listUsers.
class DashboardUser {
  final String id;
  final String name;
  final String email;
  final String domain;
  final List<String> roles;
  final bool isValidated;
  final String createdDate;

  const DashboardUser({
    required this.id,
    required this.name,
    required this.email,
    required this.domain,
    required this.roles,
    required this.isValidated,
    required this.createdDate,
  });

  factory DashboardUser.fromJson(Map<String, dynamic> m) => DashboardUser(
        id: '${m['id'] ?? ''}',
        name: '${m['name'] ?? ''}',
        email: '${m['email'] ?? ''}',
        domain: '${m['domain'] ?? ''}',
        roles: ((m['roles'] as List?) ?? []).map((r) => '$r').toList(),
        isValidated: m['isValidated'] == true,
        createdDate: '${m['createdDate'] ?? ''}',
      );
}

/// Typed view over the AdminService scheduler-status pairs.
class SchedulerStatus {
  final Map<String, String> _values;
  SchedulerStatus(this._values);

  bool get isLeader => _values['isLeader'] == 'true';
  bool get isRunning => _values['isRunning'] == 'true';
  int get totalWorkers => int.tryParse(_values['totalWorkers'] ?? '') ?? 0;
  int get availableWorkers =>
      int.tryParse(_values['availableWorkers'] ?? '') ?? 0;
  int get busyWorkers => int.tryParse(_values['busyWorkers'] ?? '') ?? 0;
  int get queueSize => int.tryParse(_values['queueSize'] ?? '') ?? 0;
  String get schedulerVersion => _values['schedulerVersion'] ?? '';
}

/// Presentation helpers over the task model.
extension TaskView on sci.Task {
  String get stateKind => state.kind;

  String get shortKind =>
      kind.endsWith('Task') ? kind.substring(0, kind.length - 4) : kind;

  String envValue(String key) {
    for (final pair in environment) {
      if (pair.key == key) return pair.value;
    }
    return '';
  }

  String get bookedCpu => envValue('cpu');
  String get bookedRam => envValue('ram');

  String get failureError {
    final s = state;
    return s is sci.FailedState ? s.error : '';
  }

  String get failureReason {
    final s = state;
    return s is sci.FailedState ? s.reason : '';
  }
}

String formatBytes(num bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 10 || unit == 0 ? 0 : 1)} ${units[unit]}';
}

String formatDuration(double seconds) {
  if (seconds <= 0) return '—';
  final d = Duration(milliseconds: (seconds * 1000).round());
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
  if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
  return '${d.inSeconds}s';
}

/// Task/worker dates are ISO strings; render compactly, local time.
String formatDate(String isoDate) {
  if (isoDate.isEmpty) return '—';
  final parsed = DateTime.tryParse(isoDate);
  if (parsed == null) return isoDate;
  final local = parsed.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
