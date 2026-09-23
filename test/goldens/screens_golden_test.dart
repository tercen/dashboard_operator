import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tercen_dashboard/src/app.dart';
import 'package:tercen_dashboard/src/theme.dart';

import '../support/fake_data.dart';

/// Every screen, in both themes, on invented data (test/support). The PNGs
/// under test/goldens/ are what the Tercen colour scheme looks like; update
/// them with `flutter test --update-goldens test/goldens`.
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
        tester.view
          ..physicalSize = const Size(1280, 800)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final theme = ThemeController();
        addTearDown(theme.dispose);

        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: DashboardTheme.light,
          darkTheme: DashboardTheme.dark,
          themeMode: mode,
          home: DashboardShell(
            session: fakeAdminSession(),
            theme: theme,
            data: FakeDashboardData(),
          ),
        ));
        await tester.tap(find.descendant(
            of: find.byType(NavigationRail), matching: find.text(section)));
        // Load, then let the workflow-name lookups resolve.
        for (var i = 0; i < 4; i++) {
          await tester.pump();
        }

        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
              '${section.toLowerCase()}_$name.png'),
        );

        // Panels refresh on a timer; unmount so none outlives the test.
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}

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
