import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tercen_dashboard/src/app.dart';
import 'package:tercen_dashboard/src/theme.dart';
import 'package:tercen_dashboard/src/widgets.dart';

import 'support/fake_data.dart';

// The fills of tercen-style icons/App.svg, row-major, typed out here rather
// than read through TercenAppIcon.colors, so a wrong copy fails instead of
// agreeing with itself.
const _svgFills = [
  0xFFFF0000, 0xFFFF8200, 0xFF99FF00, 0xFFFFBF00, // row 0
  0xFF9333EA, 0xFF0099FF, 0xFF6D0000, 0xFF66FF7F, // row 1
  0xFFE040FB, 0xFF00FFFF, 0xFF0000FF, 0xFF0D9488, // row 2
  0xFFFF4F00, 0xFFEC4899, 0xFFFFF8DC, 0xFFFFDD00, // row 3
];

void main() {
  test('the 16 colours are App.svg\'s fills, row-major', () {
    expect(TercenAppIcon.colors.map((c) => c.toARGB32()).toList(),
        _svgFills);
  });

  /// Every pixel of a 28px icon drawn under [theme], as ARGB.
  Future<List<int>> render(WidgetTester tester, ThemeData theme) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Center(
        child: RepaintBoundary(
            key: key, child: const TercenAppIcon(size: 28)),
      ),
    ));
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = (await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data =
          await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      image.dispose();
      return data!;
    }))!;
    expect(bytes.lengthInBytes, 28 * 28 * 4);
    return [
      for (var i = 0; i < bytes.lengthInBytes; i += 4)
        (bytes.getUint8(i + 3) << 24) |
            (bytes.getUint8(i) << 16) |
            (bytes.getUint8(i + 1) << 8) |
            bytes.getUint8(i + 2),
    ];
  }

  testWidgets('each 7px cell is one solid fill, no seams', (tester) async {
    final pixels = await render(tester, DashboardTheme.dark);
    for (var y = 0; y < 28; y++) {
      for (var x = 0; x < 28; x++) {
        expect(pixels[y * 28 + x], _svgFills[(y ~/ 7) * 4 + x ~/ 7],
            reason: 'pixel ($x, $y)');
      }
    }
  });

  testWidgets('the colours are the same in the white and black themes',
      (tester) async {
    final light = await render(tester, DashboardTheme.light);
    final dark = await render(tester, DashboardTheme.dark);
    expect(light, dark);
  });

  for (final (size, layout) in [
    (const Size(1280, 800), 'rail'),
    (const Size(400, 800), 'drawer'),
  ]) {
    testWidgets('the $layout shows the App icon, not Icons.hub',
        (tester) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final theme = ThemeController();
      addTearDown(theme.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: DashboardTheme.light,
        darkTheme: DashboardTheme.dark,
        home: RoleGate(
            session: fakeAdminSession(),
            theme: theme,
            data: FakeDashboardData()),
      ));
      await tester.pumpAndSettle();
      if (layout == 'drawer') {
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
      }

      final icon = find.byType(TercenAppIcon);
      expect(icon, findsOneWidget);
      expect(tester.getSize(icon), Size.square(layout == 'rail' ? 28 : 24));
      expect(find.byIcon(Icons.hub), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
