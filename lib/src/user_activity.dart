/// The answer of AdminService.listUserActivity (tercen/sci#1667): per user,
/// the last distinct objects touched and the days with activity.
library;

/// The days an activity count covers: inclusive YYYY-MM-DD UTC days, or
/// neither for all time. The Users page passes it through to the server.
class ActivityWindow {
  final String from;
  final String to;
  const ActivityWindow(this.from, this.to);
  const ActivityWindow.allTime()
      : from = '',
        to = '';

  bool get isAllTime => from.isEmpty && to.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is ActivityWindow && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => isAllTime ? 'all time' : '$from – $to';
}

/// One object a user touched: its latest touch.
class ActivityObject {
  final String kind;
  final String id;
  final String name;

  /// create, update or delete.
  final String type;
  final String date;
  final String projectId;
  final String projectName;

  /// The username in the object's link: the live project's owner. Null
  /// when the object has no project or the project is gone — no link then.
  final String? owner;

  const ActivityObject({
    required this.kind,
    required this.id,
    required this.name,
    required this.type,
    required this.date,
    required this.projectId,
    required this.projectName,
    this.owner,
  });

  bool get isDeleted => type == 'delete';

  factory ActivityObject.fromJson(Map<String, dynamic> m) {
    final owner = m['owner'];
    return ActivityObject(
      kind: '${m['kind'] ?? ''}',
      id: '${m['id'] ?? ''}',
      name: '${m['name'] ?? ''}',
      type: '${m['type'] ?? ''}',
      date: '${m['date'] ?? ''}',
      projectId: '${m['projectId'] ?? ''}',
      projectName: '${m['projectName'] ?? ''}',
      owner: owner is String && owner.isNotEmpty ? owner : null,
    );
  }
}

/// One user's activity. A count or list the server could not make is null
/// (unknown), never 0; [truncated] and [windowTruncated] mark a count as a
/// lower bound.
class UserActivity {
  final String id;
  final String name;
  final String domain;
  final int? activeDays;
  final int? activeDaysInWindow;
  final List<ActivityObject>? recent;
  final bool truncated;
  final bool windowTruncated;

  const UserActivity({
    required this.id,
    required this.name,
    required this.domain,
    this.activeDays,
    this.activeDaysInWindow,
    this.recent,
    this.truncated = false,
    this.windowTruncated = false,
  });

  factory UserActivity.fromJson(Map<String, dynamic> m) {
    int? count(Object? v) => v is num ? v.toInt() : null;
    final recent = m['recent'];
    return UserActivity(
      id: '${m['id'] ?? ''}',
      name: '${m['name'] ?? ''}',
      domain: '${m['domain'] ?? ''}',
      activeDays: count(m['activeDays']),
      activeDaysInWindow: count(m['activeDaysInWindow']),
      recent: recent is List
          ? [
              for (final r in recent)
                if (r is Map)
                  ActivityObject.fromJson(Map<String, dynamic>.from(r)),
            ]
          : null,
      truncated: m['truncated'] == true,
      windowTruncated: m['windowTruncated'] == true,
    );
  }
}

/// The whole answer, looked up per user by domain and id — the pair that
/// names a user across the domains listUsers reads.
class UserActivityReport {
  final Map<(String, String), UserActivity> _byUser;

  /// The window the server counted, or null for none.
  final ActivityWindow? window;

  /// The activities read per user; a user with more is [UserActivity.truncated].
  final int? budget;

  UserActivityReport(Iterable<UserActivity> rows, {this.window, this.budget})
      : _byUser = {for (final r in rows) (r.domain, r.id): r};

  UserActivity? operator []((String domain, String id) user) => _byUser[user];

  factory UserActivityReport.fromJson(Map<String, dynamic> m) {
    final window = m['window'];
    final budget = m['budget'];
    return UserActivityReport(
      [
        for (final r in (m['rows'] as List?) ?? const [])
          if (r is Map) UserActivity.fromJson(Map<String, dynamic>.from(r)),
      ],
      window: window is Map
          ? ActivityWindow('${window['from'] ?? ''}', '${window['to'] ?? ''}')
          : null,
      budget: budget is num ? budget.toInt() : null,
    );
  }
}
