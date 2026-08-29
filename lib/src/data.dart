import 'dart:convert';

import 'package:sci_tercen_client/sci_client.dart' as sci;

import 'session.dart';

/// Data access for the dashboard panels, on top of the existing API surface.
/// Server-side authorization is the boundary: every call here is made with the
/// session token and fails with 403 for callers without the required role.
class DashboardData {
  final DashboardSession session;

  DashboardData(this.session);

  sci.ServiceFactory get _f => session.factory;

  Future<sci.Version> tercenVersion() =>
      _f.userService.getServerVersion('tercen');

  Future<sci.Version> sarnoVersion() =>
      _f.userService.getServerVersion('sarno');

  /// Live task set known to the scheduler. Admin sees all tenants.
  Future<List<sci.Task>> tasks() => _f.taskService.getTasks([]);

  /// Registered workers. (Admin-gating is a pending server-side hardening.)
  Future<List<sci.Worker>> workers() => _f.taskService.getWorkers([]);

  Future<void> cancelTask(String taskId) => _f.taskService.cancelTask(taskId);

  Future<List<sci.User>> users({int limit = 500}) async {
    final result = await _f.userService
        .findUserByCreatedDateAndName(limit: limit, descending: true);
    return result.where((u) => u.kind == 'User').toList();
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
