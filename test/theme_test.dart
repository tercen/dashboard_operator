import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tercen_dashboard/src/theme.dart';
import 'package:tercen_dashboard/src/widgets.dart';

void main() {
  test('black is the default theme', () {
    expect(ThemeController().value, ThemeMode.dark);
  });

  test('toggling swaps between black and white', () {
    final controller = ThemeController();
    expect(controller.isDark, isTrue);
    controller.toggle();
    expect(controller.value, ThemeMode.light);
    controller.toggle();
    expect(controller.value, ThemeMode.dark);
  });

  test('the black theme paints a true black ground', () {
    expect(DashboardTheme.dark.scaffoldBackgroundColor, const Color(0xFF000000));
    expect(DashboardTheme.dark.brightness, Brightness.dark);
  });

  test('the white theme paints a white ground', () {
    expect(DashboardTheme.light.scaffoldBackgroundColor, const Color(0xFFFFFFFF));
    expect(DashboardTheme.light.brightness, Brightness.light);
  });

  test('both themes carry the semantic color set', () {
    for (final theme in [DashboardTheme.dark, DashboardTheme.light]) {
      final colors = theme.extension<DashboardColors>();
      expect(colors, isNotNull, reason: 'severity colors must be themed');
      // Severity must not collapse into the accent or into each other.
      expect(colors!.okFg, isNot(colors.badFg));
      expect(colors.warnFg, isNot(colors.badFg));
    }
  });

  testWidgets('state chips resolve against the active theme', (tester) async {
    late (Color, Color) onBlack;
    late (Color, Color) onWhite;

    Widget probe(ThemeData theme, void Function((Color, Color)) capture) =>
        Theme(
          data: theme,
          child: Builder(builder: (context) {
            capture(StateChip.colorsFor(context, Severity.bad));
            return const StateChip('FailedState');
          }),
        );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          probe(DashboardTheme.dark, (c) => onBlack = c),
          probe(DashboardTheme.light, (c) => onWhite = c),
        ]),
      ),
    ));

    expect(onBlack.$1, isNot(onWhite.$1),
        reason: "a chip must not reuse one theme's ground on the other");
    expect(onBlack.$2, isNot(onWhite.$2));
  });
}
