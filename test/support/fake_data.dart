import 'package:sci_tercen_client/sci_client.dart' as sci;

import 'package:tercen_dashboard/src/admin_api.dart';
import 'package:tercen_dashboard/src/data.dart';
import 'package:tercen_dashboard/src/session.dart';
import 'package:tercen_dashboard/src/usage.dart';

/// A signed-in admin, without a server: enough for the role gate and the
/// rail's avatar. Every name here is invented.
DashboardSession fakeAdminSession() => DashboardSession()
  ..username = 'admin'
  ..domain = '';

/// A signed-in non-admin holding [roles] (e.g. `manager`), invented.
DashboardSession fakeSession(String username, List<String> roles) =>
    DashboardSession()
      ..username = username
      ..domain = ''
      ..user = (sci.User()
        ..name = username
        ..roles.addAll(roles));

/// Every panel's data, invented. Dates carry no zone suffix so they render
/// the same whatever the machine's time zone; the usage report states its
/// own window, so the screen does not depend on today's date either.
class FakeDashboardData extends DashboardData {
  FakeDashboardData() : super(fakeAdminSession());

  static sci.Version _version(String tag, String date) => sci.Version()
    ..tag = tag
    ..date = date;

  @override
  Future<sci.Version> tercenVersion() async =>
      _version('1.17.1', '2026-09-01T09:00:00');

  @override
  Future<sci.Version> sarnoVersion() async =>
      _version('1.9.4', '2026-08-20T09:00:00');

  @override
  Future<SchedulerStatus> schedulerStatus() async => SchedulerStatus({
        'isLeader': 'true',
        'isRunning': 'true',
        'totalWorkers': '4',
        'availableWorkers': '2',
        'busyWorkers': '2',
        'queueSize': '3',
        'schedulerVersion': '2.4.0',
      });

  static sci.Task _task({
    required sci.Task task,
    required sci.State state,
    required String owner,
    required String user,
    required String domain,
    required String created,
    double duration = 0,
    String cpu = '',
    String ram = '',
    String workflowId = '',
    String stepId = '',
  }) {
    task
      ..id = 'task-$owner-$created'
      ..state = state
      ..owner = owner
      ..duration = duration
      ..createdDate = (sci.Date()..value = created);
    task.aclContext
      ..username = user
      ..domain = domain;
    for (final (key, value) in [
      ('cpu', cpu),
      ('ram', ram),
      ('workflow.id', workflowId),
      ('step.id', stepId),
    ]) {
      if (value.isNotEmpty) {
        task.environment.add(sci.Pair()
          ..key = key
          ..value = value);
      }
    }
    return task;
  }

  @override
  Future<List<sci.Task>> tasks() async => [
        _task(
          task: sci.RunComputationTask(),
          state: sci.RunningState(),
          owner: 'lab-alpha',
          user: 'ada',
          domain: '',
          created: '2026-09-21T14:05:00',
          duration: 312,
          cpu: '4',
          ram: '8589934592',
          workflowId: 'wf000000000000000001',
          stepId: 'step-cluster',
        ),
        _task(
          task: sci.RunComputationTask(),
          state: sci.PendingState(),
          owner: 'lab-alpha',
          user: 'grace',
          domain: '',
          created: '2026-09-21T14:03:00',
          cpu: '2',
          ram: '4294967296',
          workflowId: 'wf000000000000000001',
          stepId: 'step-normalise',
        ),
        _task(
          task: sci.RunComputationTask(),
          state: sci.FailedState()
            ..error = 'operator.failed'
            ..reason = 'Invented failure for the screenshot',
          owner: 'team-beta',
          user: 'linus',
          domain: 'north',
          created: '2026-09-21T13:40:00',
          duration: 48,
          cpu: '1',
          ram: '2147483648',
          workflowId: 'wf000000000000000002',
          stepId: 'step-qc',
        ),
        _task(
          task: sci.CreateGitOperatorTask(),
          state: sci.DoneState(),
          owner: 'team-beta',
          user: 'margaret',
          domain: 'north',
          created: '2026-09-21T12:10:00',
          duration: 95,
        ),
        _task(
          task: sci.RunComputationTask(),
          state: sci.CanceledState(),
          owner: 'lab-alpha',
          user: 'ada',
          domain: '',
          created: '2026-09-21T11:55:00',
          duration: 20,
        ),
      ];

  @override
  Future<WorkflowRef?> workflowRef(String workflowId) async => WorkflowRef(
        id: workflowId,
        name: workflowId.endsWith('1') ? 'Flow cytometry' : 'RNA-seq QC',
        stepNames: const {
          'step-cluster': 'Clustering',
          'step-normalise': 'Normalise',
          'step-qc': 'Quality control',
        },
      );

  @override
  String workflowUrl(String owner, String workflowId) =>
      'https://tercen.invalid/$owner/w/$workflowId';

  @override
  String projectUrl(String owner, String projectId) =>
      'https://tercen.invalid/$owner/p/$projectId';

  static sci.Worker _worker(String name, String status, int free, int cpus,
          double freeGiB, double totalGiB) =>
      sci.Worker()
        ..name = name
        ..status = status
        ..nAvailableThread = free
        ..nCPU = cpus
        ..nThread = cpus
        ..availableMemory = freeGiB * 1024 * 1024 * 1024
        ..memory = totalGiB * 1024 * 1024 * 1024
        ..lastDateActivity = '2026-09-21T14:05:00'
        ..uri = 'http://$name.invalid:5400';

  @override
  Future<List<sci.Worker>> workers() async => [
        _worker('worker-a', 'Available', 6, 8, 20, 32),
        _worker('worker-b', 'Available', 2, 8, 6, 32),
        _worker('worker-c', 'Idle', 16, 16, 60, 64),
        _worker('worker-d', 'Unavailable', 0, 8, 0, 32),
      ];

  @override
  Future<UserListing> users({int limit = UserRows.serverMaxLimit}) async =>
      UserListing(
        viaFallback: false,
        limit: limit,
        total: 5,
        truncated: false,
        users: [
          // linus's instance could not count projects: "unknown", not 0.
          for (final (name, domain, roles, validated, created, tags, owned) in [
            ('admin', '', ['admin'], true, '2025-01-10T09:00:00', ['staff'], 3),
            ('ada', '', ['user', 'manager'], true, '2026-02-03T10:30:00',
                ['pilot', 'cytometry'], 12),
            ('grace', '', ['user'], true, '2026-04-18T16:12:00', <String>[], 0),
            ('linus', 'north', ['user'], true, '2026-06-01T08:45:00',
                ['beta'], null),
            ('margaret', 'north', ['user'], false, '2026-09-20T17:20:00',
                <String>[], 1),
          ])
            DashboardUser(
              id: 'user-$name',
              name: name,
              email: '$name@example.test',
              domain: domain,
              roles: roles,
              isValidated: validated,
              createdDate: created,
              tags: tags,
              projectsOwned: owned,
              projectsOwnedReported: true,
            ),
        ],
      );

  @override
  Future<UsageReport> usageReport({
    required String scope,
    required String from,
    required String to,
    required String bucket,
  }) async {
    final previous = from.compareTo('2026-08-24') < 0;
    final ids = scope == 'team'
        ? ['lab-alpha', 'team-beta', 'team-gamma']
        : ['ada', 'grace', 'linus', 'margaret'];
    return UsageReport(
      scope: scope,
      from: previous ? '2026-07-25' : '2026-08-24',
      to: previous ? '2026-08-23' : '2026-09-22',
      bucket: 'day',
      domain: '',
      rows: [
        for (var day = 0; day < 30; day++)
          for (final (i, id) in ids.indexed)
            UsageRow(
              bucket: '2026-${day < 8 ? '08' : '09'}-'
                  '${(day < 8 ? 24 + day : day - 7).toString().padLeft(2, '0')}',
              id: id,
              n: previous ? (day * 3 + i * 5) % 11 : (day * 7 + i * 3) % 17,
              duration: ((day * 13 + i * 29) % 40) * 60.0,
              failed: (day + i) % 9 == 0 ? 2 : 0,
            ),
      ],
    );
  }

  @override
  Future<Map<String, dynamic>> storageReport() async => {
        'domain': '',
        'teams': [
          {
            'name': 'lab-alpha',
            'storageSize': 412.0 * 1024 * 1024 * 1024,
            'fileCount': 1840,
            'tableCount': 9312,
            'taskCount': 20411,
          },
          {
            'name': 'team-beta',
            'storageSize': 96.5 * 1024 * 1024 * 1024,
            'fileCount': 402,
            'tableCount': 2210,
            'taskCount': 5120,
          },
          {
            'name': 'team-gamma',
            'storageSize': 3.2 * 1024 * 1024 * 1024,
            'fileCount': 35,
            'tableCount': 180,
            'taskCount': 240,
            'error': 'summary view is stale',
          },
        ],
      };

  @override
  Future<Map<String, dynamic>> gcStatus() async => {
        'isLeader': true,
        'lastPhaseAt': '2026-09-21T13:00:00',
        'config': {'interval': '1h', 'batchSize': '500', 'dryRun': 'false'},
        'phases': [
          for (final (phase, domain, at, ms, rss, delta, error) in [
            ('tables', '', '2026-09-21T13:00:00', 4210, 812, -36, null),
            ('files', '', '2026-09-21T12:00:00', 1905, 848, 12, null),
            ('tables', 'north', '2026-09-21T11:00:00', 6620, 836, 40,
                'lease lost mid-phase'),
            ('tasks', '', '2026-09-21T10:00:00', 880, 796, -8, null),
          ])
            {
              'phase': phase,
              'domain': domain,
              'at': at,
              'elapsedMs': ms,
              'rssMi': rss,
              'rssDeltaMi': delta,
              'error': error,
            },
        ],
      };

  @override
  Future<Map<String, dynamic>> activities({int limit = 100}) async => {
        'rows': [
          for (final (date, type, kind, name, user, team, domain) in [
            ('2026-09-21T14:02:00', 'create', 'Workflow', 'Flow cytometry',
                'ada', 'lab-alpha', ''),
            ('2026-09-21T13:48:00', 'update', 'Project', 'Pilot study',
                'grace', 'lab-alpha', ''),
            ('2026-09-21T13:15:00', 'delete', 'FileDocument', 'old.csv',
                'linus', 'team-beta', 'north'),
            ('2026-09-21T12:30:00', 'changeUserPrivilege', 'User', 'margaret',
                'admin', '', 'north'),
            ('2026-09-21T11:05:00', 'rename', 'Workflow', 'RNA-seq QC',
                'linus', 'team-beta', 'north'),
            ('2026-09-21T10:40:00', 'cloneWorkflow', 'Workflow',
                'Flow cytometry (copy)', 'ada', 'lab-alpha', ''),
          ])
            {
              'date': date,
              'type': type,
              'objectKind': kind,
              'name': name,
              'userId': user,
              'teamId': team,
              'domain': domain,
            },
        ],
      };

  @override
  Future<Map<String, String>> configSummary() async => {
        'tercen.scheduler.workers': '4',
        'tercen.gc.interval': '1h',
        'tercen.signup.enabled': 'true',
        'tercen.storage.backend': 'object-store',
      };
}

/// [FakeDashboardData] with [count] invented users (`user-001`…) on the
/// Users page, reported with [total] and [truncated] as the server would.
class ManyUsersData extends FakeDashboardData {
  final int count;
  final int? total;
  final bool? truncated;
  ManyUsersData(this.count, {this.total, this.truncated});

  @override
  Future<UserListing> users({int limit = UserRows.serverMaxLimit}) async =>
      UserListing(
        viaFallback: false,
        limit: limit,
        total: total,
        truncated: truncated,
        users: [
          for (var i = 1; i <= count; i++)
            DashboardUser(
              id: 'id-$i',
              name: 'user-${i.toString().padLeft(3, '0')}',
              email: 'user$i@example.test',
              domain: i.isEven ? 'north' : '',
              roles: i % 7 == 1 ? ['user', 'manager'] : ['user'],
              isValidated: i % 5 != 2,
              createdDate: '2026-09-01T12:00:00',
            ),
        ],
      );
}

/// [FakeDashboardData] with one more user, `tagged`, whose tags are [tags]:
/// many tags, or one very long one, to show the Tags cell stays bounded.
/// [name], [roles], [domain], [validated] and [owned] make the rest of that
/// row as wide as the test needs.
class TaggedUsersData extends FakeDashboardData {
  final List<String> tags;
  final String name;
  final List<String> roles;
  final String domain;
  final bool validated;
  final int owned;
  TaggedUsersData(
    this.tags, {
    this.name = 'tagged',
    this.roles = const ['user'],
    this.domain = '',
    this.validated = true,
    this.owned = 2,
  });

  /// The widest row the fixtures allow: a name and email longer than any
  /// other fixture's, every grantable role, not validated, a domain, a
  /// four-digit project count, and a thousand tags whose first ones fill a
  /// chip, so the "+N" chip is four characters wide too. A longer [name]
  /// makes a row wider than that.
  TaggedUsersData.worstCase({String name = 'worst-case'})
      : this(
          [
            for (var i = 1; i <= 3; i++) 'W' * 40,
            for (var i = 4; i <= 1000; i++) 'tag-$i',
          ],
          name: name,
          roles: const ['user', 'manager', 'operator', 'admin'],
          domain: 'north',
          validated: false,
          owned: 1234,
        );

  @override
  Future<UserListing> users({int limit = UserRows.serverMaxLimit}) async {
    final listing = await super.users(limit: limit);
    return UserListing(
      viaFallback: false,
      limit: limit,
      total: listing.users.length + 1,
      truncated: false,
      users: [
        ...listing.users,
        DashboardUser(
          id: 'user-$name',
          name: name,
          email: '$name@example.test',
          domain: domain,
          roles: roles,
          isValidated: validated,
          createdDate: '2026-09-21T09:00:00',
          tags: tags,
          projectsOwned: owned,
          projectsOwnedReported: true,
        ),
      ],
    );
  }
}
