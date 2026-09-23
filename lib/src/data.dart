import 'dart:convert';

import 'package:sci_http_client/error.dart';
import 'package:sci_tercen_client/sci_client.dart' as sci;

import 'admin_api.dart';
import 'session.dart';
import 'usage.dart';
import 'user_activity.dart';
import 'user_filters.dart';

/// Data access for the dashboard panels, on top of the existing API surface.
/// Server-side authorization is the boundary: every call here is made with the
/// session token and fails with 403 for callers without the required role.
class DashboardData {
  final DashboardSession session;
  late final AdminApi adminApi =
      AdminApi(session.serviceBase, session.httpClient);

  /// Where per-browser choices are kept (the Users page's filters).
  final Settings settings;

  DashboardData(this.session, {this.settings = const BrowserSettings()});

  /// The time the MAU preset counts back from. Tests fix it.
  DateTime now() => DateTime.now();

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
  Future<UserListing> users({int limit = UserRows.serverMaxLimit}) async {
    try {
      final answer = await adminApi.listUsers(limit: limit);
      return UserListing(
        users: answer.rows.map(DashboardUser.fromJson).toList(),
        viaFallback: false,
        limit: limit,
        total: answer.total,
        truncated: answer.truncated,
      );
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
        limit: limit,
      );
    }
  }

  /// Per-user activity for the Users page (tercen/sci#1667), counted over
  /// [window]. Null from a server without listUserActivity: the page then
  /// leaves the activity columns blank. Slow — seconds for thousands of
  /// users — so the page loads it beside the list, never before it.
  Future<UserActivityReport?> userActivity(
      {ActivityWindow window = const ActivityWindow.allTime()}) async {
    try {
      return UserActivityReport.fromJson(await adminApi.listUserActivity(
          from: window.from, to: window.to));
    } on ServiceError catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Creates a user with UserService.createUser, built as the core admin
  /// console builds it: the name as typed, the email trimmed, and
  /// isValidated set.
  Future<void> createUser(
          {required String name,
          required String email,
          required String password}) =>
      _f.userService.createUser(
          sci.User()
            ..name = name
            ..email = email.trim()
            ..isValidated = true,
          password);

  Future<sci.ResourceSummary> userResourceSummary(String userId) =>
      _f.userService.resourceSummary(userId);

  /// Workflow name and step names for the tasks panel's provenance links,
  /// resolved once per workflow and cached for the session. Null when the
  /// workflow is gone or not readable by this role.
  final Map<String, Future<WorkflowRef?>> _workflowRefs = {};

  Future<WorkflowRef?> workflowRef(String workflowId) =>
      _workflowRefs.putIfAbsent(workflowId, () async {
        try {
          final w = await _f.workflowService.get(workflowId);
          return WorkflowRef(
            id: w.id,
            name: w.name,
            stepNames: {for (final s in w.steps) s.id: s.name},
          );
        } catch (_) {
          return null;
        }
      });

  /// Legacy web UI deep links; :owner is a name and workflow URLs have no
  /// project segment.
  String workflowUrl(String owner, String workflowId) =>
      session.serviceBase.replace(path: '/$owner/w/$workflowId').toString();

  String projectUrl(String owner, String projectId) =>
      session.serviceBase.replace(path: '/$owner/p/$projectId').toString();

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
///
/// [total] and [truncated] are null when the server does not report them
/// (before tercen/sci#1663, and always on the fallback).
class UserListing {
  final List<DashboardUser> users;
  final bool viaFallback;

  /// The limit the list was requested with.
  final int limit;
  final int? total;
  final bool? truncated;

  const UserListing({
    required this.users,
    required this.viaFallback,
    this.limit = UserRows.serverMaxLimit,
    this.total,
    this.truncated,
  });

  /// Whether users exist beyond [users]: the server says so, or — when it
  /// reports nothing — the list filled the whole [limit], so it may have
  /// stopped there.
  bool get mayHaveMore =>
      truncated ??
      (total != null ? users.length < total! : users.length >= limit);
}

/// A workflow's name and step names, for rendering task provenance.
class WorkflowRef {
  final String id;
  final String name;
  final Map<String, String> stepNames;
  const WorkflowRef(
      {required this.id, required this.name, required this.stepNames});
}

/// A user row from AdminService.listUsers.
///
/// [tags] and [projectsOwned] are what the server reports and nothing more: a key the server does not send stays null, and the table
/// leaves its cell blank.
class DashboardUser {
  final String id;
  final String name;
  final String email;
  final String domain;
  final List<String> roles;
  final bool isValidated;
  final String createdDate;

  /// `User.tags`, from a server with tercen/sci#1664; null before it. Only
  /// the non-empty strings: a null or non-string entry is dropped, so it
  /// never renders as a "null" chip.
  final List<String>? tags;

  /// Live projects the user owns (tercen/sci#1664). Null both when the key
  /// is absent and when the server sent null — [projectsOwnedReported] tells
  /// them apart: absent is an older server, null is a count the server could
  /// not make.
  final int? projectsOwned;
  final bool projectsOwnedReported;

  const DashboardUser({
    required this.id,
    required this.name,
    required this.email,
    required this.domain,
    required this.roles,
    required this.isValidated,
    required this.createdDate,
    this.tags,
    this.projectsOwned,
    this.projectsOwnedReported = false,
  });

  factory DashboardUser.fromJson(Map<String, dynamic> m) {
    final tags = m['tags'];
    final owned = m['projectsOwned'];
    return DashboardUser(
      id: '${m['id'] ?? ''}',
      name: '${m['name'] ?? ''}',
      email: '${m['email'] ?? ''}',
      domain: '${m['domain'] ?? ''}',
      roles: ((m['roles'] as List?) ?? []).map((r) => '$r').toList(),
      isValidated: m['isValidated'] == true,
      createdDate: '${m['createdDate'] ?? ''}',
      tags: tags is List
          ? [
              for (final t in tags)
                if (t is String && t.isNotEmpty) t,
            ]
          : null,
      projectsOwned: owned is num ? owned.toInt() : null,
      projectsOwnedReported: m.containsKey('projectsOwned'),
    );
  }
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

  /// Provenance stamped by the step that created the task
  /// ("workflow.id"/"step.id" environment pairs, Tercen >= 1.0.16).
  /// RunWorkflowTask carries the workflow as a field instead of a stamp.
  String get workflowId {
    final t = this;
    if (t is sci.RunWorkflowTask && t.workflowId.isNotEmpty) {
      return t.workflowId;
    }
    return envValue('workflow.id');
  }
  String get stepId => envValue('step.id');

  /// Project the task belongs to, when the task kind carries one.
  String get taskProjectId {
    final t = this;
    return t is sci.ProjectTask ? t.projectId : '';
  }

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
