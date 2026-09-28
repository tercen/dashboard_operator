import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sci_http_client/error.dart';

import 'package:tercen_dashboard/src/app.dart';
import 'package:tercen_dashboard/src/session.dart';
import 'package:tercen_dashboard/src/theme.dart';

import '../support/fake_data.dart';

/// Every screen, in both themes, on invented data (test/support), plus the
/// narrow layout with its drawer open, the "Not authorized" page, the
/// manager's shell, the Users table paged and truncated, and the Create user
/// dialog filled in and refused. The PNGs under test/goldens/ are what the
/// Tercen colour scheme looks like; update them with
/// `flutter test --update-goldens test/goldens`.
void main() {
  setUpAll(_loadFonts);

  const sections = [
    'Overview',
    'Usage',
    'Tasks',
    'Workers',
    'Users',
    'Storage',
    'GC',
    'Audit',
    'Settings',
  ];

  for (final (mode, name) in [
    (ThemeMode.dark, 'black'),
    (ThemeMode.light, 'white'),
  ]) {
    for (final section in sections) {
      testWidgets('$section, $name theme', (tester) async {
        await _pumpApp(tester, mode, fakeAdminSession());
        await tester.tap(find.descendant(
            of: find.byType(NavigationRail), matching: find.text(section)));
        await tester.pumpAndSettle();

        // The capture shows the screen that was asked for, not a frame of
        // the rail still moving off Overview.
        _expectSelected(tester, sections.indexOf(section));
        await _expectGolden('${section.toLowerCase()}_$name.png');
        await _unmount(tester);
      });
    }

    // The Users table past one page: on page 2 of 3, scrolled down to the
    // pager, with its rows-per-page menu and first/last buttons.
    testWidgets('Users, many pages, $name theme', (tester) async {
      await _pumpApp(tester, mode, fakeAdminSession(),
          data: ManyUsersData(120, total: 120, truncated: false));
      await tester.tap(find.descendant(
          of: find.byType(NavigationRail), matching: find.text('Users')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();

      expect(find.text('51–100 of 120'), findsOneWidget);
      expect(find.text('Rows per page:'), findsOneWidget);
      _expectSelected(tester, sections.indexOf('Users'));
      await _expectGolden('users_paged_$name.png');
      await _unmount(tester);
    });

    // A server that returned only part of the list says so above the table.
    testWidgets('Users, truncated, $name theme', (tester) async {
      await _pumpApp(tester, mode, fakeAdminSession(),
          data: ManyUsersData(1000, total: 1840, truncated: true));
      await tester.tap(find.descendant(
          of: find.byType(NavigationRail), matching: find.text('Users')));
      await tester.pumpAndSettle();

      expect(
          find.text('Showing 1000 of 1840 users — the server returned only '
              'the first 1000'),
          findsOneWidget);
      _expectSelected(tester, sections.indexOf('Users'));
      await _expectGolden('users_truncated_$name.png');
      await _unmount(tester);
    });

    // The Create user dialog, filled in with an invented user, and the same
    // dialog after the server refused it: the error shown, the input kept.
    for (final (state, data) in [
      ('filled', FakeDashboardData()),
      ('refused', _RefusingData()),
    ]) {
      testWidgets('Create user dialog, $state, $name theme', (tester) async {
        await _pumpApp(tester, mode, fakeAdminSession(), data: data);
        await tester.tap(find.descendant(
            of: find.byType(NavigationRail), matching: find.text('Users')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Create user'));
        await tester.pumpAndSettle();
        await tester.enterText(
            find.byKey(const Key('create-user-name')), 'new-user');
        await tester.enterText(find.byKey(const Key('create-user-email')),
            'new.user@example.test');
        await tester.enterText(
            find.byKey(const Key('create-user-password')), 'invented');
        if (state == 'refused') {
          await tester.tap(find.widgetWithText(FilledButton, 'Create'));
        }
        // The caret blinks; settle on a fixed frame without the focus.
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('create-user-error')),
            state == 'refused' ? findsOneWidget : findsNothing);
        await _expectGolden('create_user_${state}_$name.png');
        await _unmount(tester);
      });
    }

    testWidgets('narrow layout, drawer open, $name theme', (tester) async {
      await _pumpApp(tester, mode, fakeAdminSession(),
          size: const Size(390, 844));
      expect(find.byType(NavigationRail), findsNothing);
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();

      expect(find.byType(Drawer), findsOneWidget);
      await _expectGolden('narrow_drawer_$name.png');
      await _unmount(tester);
    });

    testWidgets('not authorized, $name theme', (tester) async {
      await _pumpApp(tester, mode, fakeSession('ada', const []));

      expect(find.text('Not authorized'), findsOneWidget);
      expect(find.byType(DashboardShell), findsNothing);
      await _expectGolden('not_authorized_$name.png');
      await _unmount(tester);
    });

    testWidgets('manager shell, $name theme', (tester) async {
      await _pumpApp(tester, mode, fakeSession('grace', const ['manager']));

      // A manager without admin gets the usage views only.
      final rail =
          tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.destinations, hasLength(1));
      expect(find.text('Usage'), findsWidgets);
      _expectSelected(tester, 0);
      await _expectGolden('manager_$name.png');
      await _unmount(tester);
    });
  }
}

/// [FakeDashboardData] whose server refuses every new user, with an
/// invented reason.
class _RefusingData extends FakeDashboardData {
  @override
  Future<void> createUser(
          {required String name,
          required String email,
          required String password}) async =>
      throw ServiceError(400, 'user.create.username.not.available',
          'Username "$name" is not available.');
}

/// The real app below the session: [RoleGate] picks the shell or the
/// "Not authorized" page, as it does in the browser. Pumped to rest.
Future<void> _pumpApp(
  WidgetTester tester,
  ThemeMode mode,
  DashboardSession session, {
  Size size = const Size(1280, 800),
  FakeDashboardData? data,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final theme = ThemeController();
  addTearDown(theme.dispose);

  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: DashboardTheme.light,
    darkTheme: DashboardTheme.dark,
    themeMode: mode,
    home: RoleGate(
      session: session,
      theme: theme,
      data: data ?? FakeDashboardData(),
    ),
  ));
  // Load, let the workflow-name lookups resolve, and finish every
  // transition before anything is captured.
  await tester.pumpAndSettle();
}

void _expectSelected(WidgetTester tester, int index) {
  final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
  expect(rail.selectedIndex, index);
  expect(tester.binding.hasScheduledFrame, isFalse,
      reason: 'an animation is still running');
}

Future<void> _expectGolden(String file) => expectLater(
    find.byType(MaterialApp), matchesGoldenFile(file));

/// Panels refresh on a timer; unmount so none outlives the test.
Future<void> _unmount(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox.shrink());

/// `flutter test` draws every glyph as a box unless fonts are loaded:
/// load the app's own (Fira Sans, Material Icons) from the font manifest.
/// There is no bundled monospace face, so ids and URIs are drawn in Fira
/// Sans here; in a browser they get the system monospace.
Future<void> _loadFonts() async {
  final manifest = json.decode(
      await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
  for (final family in manifest.cast<Map<String, dynamic>>()) {
    final name = family['family'] as String;
    final assets = [
      for (final font in (family['fonts'] as List).cast<Map>())
        '${font['asset']}',
    ];
    for (final loaderName in [
      name,
      if (name == TercenTokens.fontFamily) 'monospace',
    ]) {
      final loader = FontLoader(loaderName);
      for (final asset in assets) {
        loader.addFont(rootBundle.load(asset));
      }
      await loader.load();
    }
  }
}
