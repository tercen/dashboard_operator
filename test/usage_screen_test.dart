import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tercen_dashboard/src/data.dart';
import 'package:tercen_dashboard/src/session.dart';
import 'package:tercen_dashboard/src/usage.dart';
import 'package:tercen_dashboard/src/screens/usage_screen.dart';

/// Counts usage fetches per window so a refresh tick can be told apart from a
/// cache hit.
class _CountingData extends DashboardData {
  _CountingData() : super(DashboardSession());

  final calls = <String, int>{};

  @override
  Future<UsageReport> usageReport({
    required String scope,
    required String from,
    required String to,
    required String bucket,
  }) async {
    final key = '$from..$to';
    calls[key] = (calls[key] ?? 0) + 1;
    return UsageReport(
        scope: scope,
        from: from,
        to: to,
        bucket: bucket,
        domain: 'test',
        rows: const []);
  }
}

/// The Usage panel refreshes on a 5-minute timer, and each load asks for two
/// windows: the current period and the one before it for the trend deltas.
/// The comparison window is entirely in the past, so refetching it every tick
/// doubles the server cost of an open tab to buy a number that cannot change —
/// and on a large tenant that aggregate is expensive (tercen/sci#1231).
void main() {
  testWidgets('the comparison window is fetched once across refresh ticks',
      (tester) async {
    // The panel's action row needs a desktop-width surface; the default
    // 800x600 test window overflows it and the overflow is reported as a
    // failure.
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final data = _CountingData();

    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: UsageScreen(data: data))));
    await tester.pumpAndSettle();

    expect(data.calls.length, 2,
        reason: 'first load asks for the current and comparison windows');
    final windows = data.calls.keys.toList()..sort();
    final comparison = windows.first; // earlier range sorts first
    final current = windows.last;
    expect(data.calls[current], 1);
    expect(data.calls[comparison], 1);

    // Two refresh ticks.
    await tester.pump(const Duration(minutes: 5));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 5));
    await tester.pumpAndSettle();

    expect(data.calls[current], 3,
        reason: 'the current window is live and must refresh every tick');
    expect(data.calls[comparison], 1,
        reason: 'the comparison window has closed and must not be refetched');

    // Dispose the screen so its periodic timer does not outlive the test.
    // Keep the MaterialApp so teardown can still resolve ancestors.
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())));
    await tester.pumpAndSettle();
  });
}
