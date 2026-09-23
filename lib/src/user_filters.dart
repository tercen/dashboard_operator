/// The Users page's filter bar: an activity window, the MAU preset, and
/// email domains to leave out. Kept per browser.
library;

import 'dart:convert';

import 'data.dart';
import 'platform/platform_stub.dart'
    if (dart.library.js_interop) 'platform/platform_web.dart' as platform;
import 'user_activity.dart';

/// Durable per-browser settings: localStorage in the browser, nothing off
/// it. Tests pass [MemorySettings].
abstract class Settings {
  String read(String key);
  void write(String key, String value);
}

class BrowserSettings implements Settings {
  const BrowserSettings();

  @override
  String read(String key) => platform.readSetting(key);

  @override
  void write(String key, String value) => platform.writeSetting(key, value);
}

class MemorySettings implements Settings {
  final Map<String, String> values;
  MemorySettings([Map<String, String>? values]) : values = values ?? {};

  @override
  String read(String key) => values[key] ?? '';

  @override
  void write(String key, String value) => values[key] = value;
}

/// What the activity window is: none, dates the admin chose, or the MAU
/// preset — the last 30 days up to today, whatever day it is loaded on.
enum WindowMode { allTime, custom, mau }

/// A YYYY-MM-DD day, as the server takes it (tercen/sci#1667).
String formatDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// The part of [email] after its last "@", lower-cased; empty without one.
String emailDomain(String email) {
  final at = email.lastIndexOf('@');
  return at < 0 ? '' : email.substring(at + 1).trim().toLowerCase();
}

/// An exclusion as typed — "@Example.TEST " — reduced to "example.test".
String normalizeDomain(String typed) {
  var d = typed.trim().toLowerCase();
  while (d.startsWith('@')) {
    d = d.substring(1);
  }
  return d;
}

class UserFilters {
  static const storageKey = 'tercen.dashboard.users.filters';

  /// The MAU preset's length in days, today included.
  static const mauDays = 30;

  final WindowMode mode;

  /// The chosen days in [WindowMode.custom]; unused otherwise.
  final String from;
  final String to;

  /// Email domains whose users leave the rows and every count. Exact,
  /// case-insensitive matches: excluding a domain does not exclude its
  /// subdomains.
  final List<String> excluded;

  const UserFilters({
    this.mode = WindowMode.allTime,
    this.from = '',
    this.to = '',
    this.excluded = const [],
  });

  bool get isMau => mode == WindowMode.mau;

  /// The window to ask the server for, on the UTC day of [now].
  ActivityWindow window(DateTime now) {
    switch (mode) {
      case WindowMode.allTime:
        return const ActivityWindow.allTime();
      case WindowMode.custom:
        return ActivityWindow(from, to);
      case WindowMode.mau:
        final utc = now.toUtc();
        final today = DateTime.utc(utc.year, utc.month, utc.day);
        return ActivityWindow(
            formatDay(today.subtract(const Duration(days: mauDays - 1))),
            formatDay(today));
    }
  }

  bool excludes(DashboardUser user) =>
      excluded.isNotEmpty && excluded.contains(emailDomain(user.email));

  UserFilters copyWith(
          {WindowMode? mode,
          String? from,
          String? to,
          List<String>? excluded}) =>
      UserFilters(
        mode: mode ?? this.mode,
        from: from ?? this.from,
        to: to ?? this.to,
        excluded: excluded ?? this.excluded,
      );

  Map<String, Object?> toJson() => {
        'mode': mode.name,
        if (mode == WindowMode.custom) 'from': from,
        if (mode == WindowMode.custom) 'to': to,
        'excluded': excluded,
      };

  /// What [toJson] wrote; anything it cannot read falls back to the
  /// default for that part: a stored setting never breaks the page.
  factory UserFilters.fromJson(Object? json) {
    if (json is! Map) return const UserFilters();
    final day = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    final from = '${json['from'] ?? ''}';
    final to = '${json['to'] ?? ''}';
    var mode = WindowMode.values
        .firstWhere((m) => m.name == json['mode'], orElse: () => WindowMode.allTime);
    if (mode == WindowMode.custom &&
        !(day.hasMatch(from) && day.hasMatch(to) && from.compareTo(to) <= 0)) {
      mode = WindowMode.allTime;
    }
    final excluded = json['excluded'];
    return UserFilters(
      mode: mode,
      from: mode == WindowMode.custom ? from : '',
      to: mode == WindowMode.custom ? to : '',
      excluded: excluded is List
          ? {
              for (final d in excluded)
                if (d is String && normalizeDomain(d).isNotEmpty)
                  normalizeDomain(d),
            }.toList()
          : const [],
    );
  }

  static UserFilters load(Settings settings) {
    final stored = settings.read(storageKey);
    if (stored.isEmpty) return const UserFilters();
    try {
      return UserFilters.fromJson(json.decode(stored));
    } on FormatException {
      return const UserFilters();
    }
  }

  void save(Settings settings) =>
      settings.write(storageKey, json.encode(toJson()));
}

/// Whether a user was active in the window, as far as the server's answer
/// tells: yes (at least one day), no (zero days, counted in full), or
/// unknown — no count, a user the answer does not name, or a lower bound
/// of zero ("≥0": the server stopped reading before it could tell).
enum WindowActivity { active, inactive, unknown }

WindowActivity windowActivity(UserActivity? activity) {
  final days = activity?.activeDaysInWindow;
  if (activity == null || days == null) return WindowActivity.unknown;
  if (days > 0) return WindowActivity.active;
  return activity.windowTruncated
      ? WindowActivity.unknown
      : WindowActivity.inactive;
}
