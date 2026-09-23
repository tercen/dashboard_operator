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

  // Expected values are the hex strings of tercen-style tokens.json 1.1.0,
  // typed out here rather than read through TercenTokens, so a wrong copy
  // in theme.dart fails instead of agreeing with itself.
  const tokens = {
    Brightness.light: {
      'primary': 0xFF1E40AF,
      'onPrimary': 0xFFFFFFFF,
      'primaryContainer': 0xFFDBEAFE,
      'secondary': 0xFF2563EB,
      'tertiary': 0xFF6D28D9,
      'error': 0xFFB91C1C,
      'errorContainer': 0xFFFEE2E2,
      'background': 0xFFF3F4F6,
      'surface': 0xFFFFFFFF,
      'onSurface': 0xFF111827,
      'onSurfaceVariant': 0xFF374151,
      'onSurfaceMuted': 0xFF6B7280,
      'surfaceContainerLow': 0xFFF9FAFB,
      'surfaceContainer': 0xFFF3F4F6,
      'surfaceContainerHighest': 0xFFD1D5DB,
      'outline': 0xFFD1D5DB,
      'outlineVariant': 0xFFE5E7EB,
      'inverseSurface': 0xFF111827,
      'panelBg': 0xFFF9FAFB,
      'success': 0xFF047857,
      'successContainer': 0xFFD1FAE5,
      'warning': 0xFFB45309,
      'warningContainer': 0xFFFEF3C7,
      'info': 0xFF0E7490,
      'infoContainer': 0xFFCFFAFE,
      'textTertiary': 0xFF4B5563,
    },
    Brightness.dark: {
      'primary': 0xFF14B8A6,
      'onPrimary': 0xFFFFFFFF,
      'primaryContainer': 0xFF153D47,
      'secondary': 0xFF2DD4BF,
      'tertiary': 0xFFA78BFA,
      'error': 0xFFF87171,
      'errorContainer': 0xFF450A0A,
      'background': 0xFF0A0A0A,
      'surface': 0xFF111827,
      'onSurface': 0xFFF9FAFB,
      'onSurfaceVariant': 0xFFE5E7EB,
      'onSurfaceMuted': 0xFF6B7280,
      'surfaceContainerLow': 0xFF111827,
      'surfaceContainer': 0xFF1F2937,
      'surfaceContainerHighest': 0xFF374151,
      'outline': 0xFF374151,
      'outlineVariant': 0xFF374151,
      'inverseSurface': 0xFFF9FAFB,
      'panelBg': 0xFF111827,
      'success': 0xFF10B981,
      'successContainer': 0xFF14532D,
      'warning': 0xFFFBBF24,
      'warningContainer': 0xFF451A03,
      'info': 0xFF60A5FA,
      'infoContainer': 0xFF083344,
      'textTertiary': 0xFF9CA3AF,
    },
  };

  for (final (name, theme) in [
    ('black', DashboardTheme.dark),
    ('white', DashboardTheme.light),
  ]) {
    group('the $name theme uses the Tercen tokens', () {
      final t = tokens[theme.brightness]!;
      Color token(String key) => Color(t[key]!);
      final scheme = theme.colorScheme;

      test('ColorScheme', () {
        expect(scheme.brightness, theme.brightness);
        expect(scheme.primary, token('primary'));
        expect(scheme.onPrimary, token('onPrimary'));
        expect(scheme.primaryContainer, token('primaryContainer'));
        expect(scheme.secondary, token('secondary'));
        expect(scheme.tertiary, token('tertiary'));
        expect(scheme.error, token('error'));
        expect(scheme.errorContainer, token('errorContainer'));
        expect(scheme.surface, token('surface'));
        expect(scheme.onSurface, token('onSurface'));
        expect(scheme.onSurfaceVariant, token('onSurfaceVariant'));
        expect(scheme.surfaceContainerLow, token('surfaceContainerLow'));
        expect(scheme.surfaceContainer, token('surfaceContainer'));
        expect(
            scheme.surfaceContainerHighest, token('surfaceContainerHighest'));
        expect(scheme.outline, token('outline'));
        expect(scheme.outlineVariant, token('outlineVariant'));
        expect(scheme.inverseSurface, token('inverseSurface'));
      });

      test('page ground, left rail and table header', () {
        expect(theme.scaffoldBackgroundColor, token('background'));
        expect(theme.navigationRailTheme.backgroundColor, token('panelBg'));
        expect(theme.navigationRailTheme.indicatorColor,
            token('primaryContainer'));
        expect(theme.dataTableTheme.headingRowColor?.resolve({}),
            token('surfaceContainerLow'));
        expect(theme.cardTheme.color, token('surface'));
      });

      test('muted text is onSurfaceMuted, never a border colour', () {
        expect(theme.textTheme.bodySmall?.color, token('onSurfaceMuted'));
        expect(theme.textTheme.bodySmall?.color, isNot(scheme.outline));
      });

      test('status chips are the <status>Container pairs', () {
        final c = theme.extension<DashboardColors>()!;
        final dark = theme.brightness == Brightness.dark;
        expect(c.okBg, token('successContainer'));
        expect(c.warnBg, token('warningContainer'));
        expect(c.badBg, token('errorContainer'));
        expect(c.infoBg, token('infoContainer'));
        expect(c.neutralBg, token('surfaceContainer'));
        expect(c.neutralFg, token('textTertiary'));
        // on<Status>Container: the status ink itself in the white theme; in
        // the black theme error and warning match and success and info are
        // the lighter tints tokens.json gives.
        expect(c.badFg, token('error'));
        expect(c.warnFg, token('warning'));
        expect(c.okFg, dark ? const Color(0xFF4ADE80) : token('success'));
        expect(c.infoFg, dark ? const Color(0xFF67E8F9) : token('info'));
      });

      test('Fira Sans is the typeface', () {
        expect(theme.textTheme.bodyMedium?.fontFamily, 'Fira Sans');
        expect(theme.textTheme.headlineSmall?.fontFamily, 'Fira Sans');
        // Component styles set explicitly do not inherit ThemeData's font.
        for (final style in [
          // Buttons read labelLarge, which Typography sets a family on.
          theme.textTheme.labelLarge,
          theme.navigationRailTheme.selectedLabelTextStyle,
          theme.navigationRailTheme.unselectedLabelTextStyle,
          theme.dataTableTheme.headingTextStyle,
          theme.dataTableTheme.dataTextStyle,
          theme.tooltipTheme.textStyle,
        ]) {
          expect(style?.fontFamily, 'Fira Sans');
        }
      });
    });
  }

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
