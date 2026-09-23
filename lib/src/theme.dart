import 'package:flutter/material.dart';

import 'platform/platform_stub.dart'
    if (dart.library.js_interop) 'platform/platform_web.dart' as platform;

/// Semantic colors that are not part of Material's ColorScheme: the
/// good/warning/critical trio used by state chips and KPI values. Kept
/// separate from the accent so severity never competes with branding.
@immutable
class DashboardColors extends ThemeExtension<DashboardColors> {
  final Color okBg;
  final Color okFg;
  final Color warnBg;
  final Color warnFg;
  final Color badBg;
  final Color badFg;
  final Color infoBg;
  final Color infoFg;
  final Color neutralBg;
  final Color neutralFg;

  /// Link text (`link`): blue in both themes, so a link never reads as a
  /// primary action.
  final Color link;

  const DashboardColors({
    required this.okBg,
    required this.okFg,
    required this.warnBg,
    required this.warnFg,
    required this.badBg,
    required this.badFg,
    required this.infoBg,
    required this.infoFg,
    required this.neutralBg,
    required this.neutralFg,
    required this.link,
  });

  // Tercen status tokens (tercen-style tokens.json): each pair is the
  // <status>Container ground with its on<Status>Container ink. Neutral is
  // the neutral badge: surfaceContainer with textTertiary.
  static const dark = DashboardColors(
    okBg: TercenTokens.darkSuccessContainer,
    okFg: TercenTokens.darkOnSuccessContainer,
    warnBg: TercenTokens.darkWarningContainer,
    warnFg: TercenTokens.darkOnWarningContainer,
    badBg: TercenTokens.darkErrorContainer,
    badFg: TercenTokens.darkOnErrorContainer,
    infoBg: TercenTokens.darkInfoContainer,
    infoFg: TercenTokens.darkOnInfoContainer,
    neutralBg: TercenTokens.darkSurfaceContainer,
    neutralFg: TercenTokens.darkTextTertiary,
    link: TercenTokens.darkLink,
  );

  static const light = DashboardColors(
    okBg: TercenTokens.lightSuccessContainer,
    okFg: TercenTokens.lightOnSuccessContainer,
    warnBg: TercenTokens.lightWarningContainer,
    warnFg: TercenTokens.lightOnWarningContainer,
    badBg: TercenTokens.lightErrorContainer,
    badFg: TercenTokens.lightOnErrorContainer,
    infoBg: TercenTokens.lightInfoContainer,
    infoFg: TercenTokens.lightOnInfoContainer,
    neutralBg: TercenTokens.lightSurfaceContainer,
    neutralFg: TercenTokens.lightTextTertiary,
    link: TercenTokens.lightLink,
  );

  @override
  DashboardColors copyWith({
    Color? okBg,
    Color? okFg,
    Color? warnBg,
    Color? warnFg,
    Color? badBg,
    Color? badFg,
    Color? infoBg,
    Color? infoFg,
    Color? neutralBg,
    Color? neutralFg,
    Color? link,
  }) {
    return DashboardColors(
      okBg: okBg ?? this.okBg,
      okFg: okFg ?? this.okFg,
      warnBg: warnBg ?? this.warnBg,
      warnFg: warnFg ?? this.warnFg,
      badBg: badBg ?? this.badBg,
      badFg: badFg ?? this.badFg,
      infoBg: infoBg ?? this.infoBg,
      infoFg: infoFg ?? this.infoFg,
      neutralBg: neutralBg ?? this.neutralBg,
      neutralFg: neutralFg ?? this.neutralFg,
      link: link ?? this.link,
    );
  }

  @override
  DashboardColors lerp(ThemeExtension<DashboardColors>? other, double t) {
    if (other is! DashboardColors) return this;
    return DashboardColors(
      okBg: Color.lerp(okBg, other.okBg, t)!,
      okFg: Color.lerp(okFg, other.okFg, t)!,
      warnBg: Color.lerp(warnBg, other.warnBg, t)!,
      warnFg: Color.lerp(warnFg, other.warnFg, t)!,
      badBg: Color.lerp(badBg, other.badBg, t)!,
      badFg: Color.lerp(badFg, other.badFg, t)!,
      infoBg: Color.lerp(infoBg, other.infoBg, t)!,
      infoFg: Color.lerp(infoFg, other.infoFg, t)!,
      neutralBg: Color.lerp(neutralBg, other.neutralBg, t)!,
      neutralFg: Color.lerp(neutralFg, other.neutralFg, t)!,
      link: Color.lerp(link, other.link, t)!,
    );
  }
}

/// Tercen's colour tokens, copied from tercen-style `tokens.json` (1.1.0),
/// which is authoritative: where the two disagree, this file is wrong.
/// Names are the `tokens.json` paths, prefixed by theme.
abstract final class TercenTokens {
  /// `fontFamily`; the Fira Sans files are bundled under `fonts/`.
  static const fontFamily = 'Fira Sans';

  // themes.light.colors
  static const lightPrimary = Color(0xFF1E40AF);
  static const lightOnPrimary = Color(0xFFFFFFFF);
  static const lightPrimaryContainer = Color(0xFFDBEAFE);
  static const lightOnPrimaryContainer = Color(0xFF1E3A8A);
  static const lightPrimaryHover = Color(0xFF1E3A8A);
  static const lightPrimaryActive = Color(0xFF2563EB);
  static const lightSecondary = Color(0xFF2563EB);
  static const lightOnSecondary = Color(0xFFFFFFFF);
  static const lightSecondaryContainer = Color(0xFFDBEAFE);
  static const lightOnSecondaryContainer = Color(0xFF1E40AF);
  static const lightTertiary = Color(0xFF6D28D9);
  static const lightOnTertiary = Color(0xFFFFFFFF);
  static const lightTertiaryContainer = Color(0xFFEDE9FE);
  static const lightOnTertiaryContainer = Color(0xFF6D28D9);
  static const lightError = Color(0xFFB91C1C);
  static const lightOnError = Color(0xFFFFFFFF);
  static const lightErrorContainer = Color(0xFFFEE2E2);
  static const lightOnErrorContainer = Color(0xFFB91C1C);
  static const lightBackground = Color(0xFFF3F4F6);
  static const lightOnBackground = Color(0xFF111827);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightOnSurface = Color(0xFF111827);
  static const lightOnSurfaceVariant = Color(0xFF374151);
  static const lightOnSurfaceMuted = Color(0xFF6B7280);
  static const lightOnSurfaceDisabled = Color(0xFF9CA3AF);
  static const lightSurfaceContainerLowest = Color(0xFFFFFFFF);
  static const lightSurfaceContainerLow = Color(0xFFF9FAFB);
  static const lightSurfaceContainer = Color(0xFFF3F4F6);
  static const lightSurfaceContainerHigh = Color(0xFFE5E7EB);
  static const lightSurfaceContainerHighest = Color(0xFFD1D5DB);
  static const lightOutline = Color(0xFFD1D5DB);
  static const lightOutlineVariant = Color(0xFFE5E7EB);
  static const lightInverseSurface = Color(0xFF111827);
  static const lightOnInverseSurface = Color(0xFFF9FAFB);
  static const lightInversePrimary = Color(0xFF93C5FD);
  static const lightScrim = Color(0xFF000000);
  static const lightShadow = Color(0xFF000000);
  static const lightWarning = Color(0xFFB45309);
  static const lightOnWarning = Color(0xFFFFFFFF);
  static const lightWarningContainer = Color(0xFFFEF3C7);
  static const lightOnWarningContainer = Color(0xFFB45309);
  static const lightSuccess = Color(0xFF047857);
  static const lightOnSuccess = Color(0xFFFFFFFF);
  static const lightSuccessContainer = Color(0xFFD1FAE5);
  static const lightOnSuccessContainer = Color(0xFF047857);
  static const lightInfo = Color(0xFF0E7490);
  static const lightOnInfo = Color(0xFFFFFFFF);
  static const lightInfoContainer = Color(0xFFCFFAFE);
  static const lightOnInfoContainer = Color(0xFF0E7490);
  static const lightLink = Color(0xFF2563EB);
  static const lightLinkHover = Color(0xFF1E40AF);
  static const lightPanelBg = Color(0xFFF9FAFB);
  static const lightSectionHeaderBg = Color(0xFFE5E7EB);
  static const lightTextTertiary = Color(0xFF4B5563);
  static const lightPrimaryBg = Color(0xFFEFF6FF);

  // themes.dark.colors
  static const darkPrimary = Color(0xFF14B8A6);
  static const darkOnPrimary = Color(0xFFFFFFFF);
  static const darkPrimaryContainer = Color(0xFF153D47);
  static const darkOnPrimaryContainer = Color(0xFF2DD4BF);
  static const darkPrimaryHover = Color(0xFF0D9488);
  static const darkPrimaryActive = Color(0xFF2DD4BF);
  static const darkSecondary = Color(0xFF2DD4BF);
  static const darkOnSecondary = Color(0xFF111827);
  static const darkSecondaryContainer = Color(0xFF153D47);
  static const darkOnSecondaryContainer = Color(0xFF2DD4BF);
  static const darkTertiary = Color(0xFFA78BFA);
  static const darkOnTertiary = Color(0xFF0F172A);
  static const darkTertiaryContainer = Color(0xFF2E1065);
  static const darkOnTertiaryContainer = Color(0xFFA78BFA);
  static const darkError = Color(0xFFF87171);
  static const darkOnError = Color(0xFFFFFFFF);
  static const darkErrorContainer = Color(0xFF450A0A);
  static const darkOnErrorContainer = Color(0xFFF87171);
  static const darkBackground = Color(0xFF0A0A0A);
  static const darkOnBackground = Color(0xFFF9FAFB);
  static const darkSurface = Color(0xFF111827);
  static const darkOnSurface = Color(0xFFF9FAFB);
  static const darkOnSurfaceVariant = Color(0xFFE5E7EB);
  static const darkOnSurfaceMuted = Color(0xFF6B7280);
  static const darkOnSurfaceDisabled = Color(0xFF4B5563);
  static const darkSurfaceContainerLowest = Color(0xFF0A0A0A);
  static const darkSurfaceContainerLow = Color(0xFF111827);
  static const darkSurfaceContainer = Color(0xFF1F2937);
  static const darkSurfaceContainerHigh = Color(0xFF1F2937);
  static const darkSurfaceContainerHighest = Color(0xFF374151);
  static const darkOutline = Color(0xFF374151);
  static const darkOutlineVariant = Color(0xFF374151);
  static const darkInverseSurface = Color(0xFFF9FAFB);
  static const darkOnInverseSurface = Color(0xFF111827);
  static const darkInversePrimary = Color(0xFF0D9488);
  static const darkScrim = Color(0xFF000000);
  static const darkShadow = Color(0xFF000000);
  static const darkWarning = Color(0xFFFBBF24);
  static const darkOnWarning = Color(0xFF111827);
  static const darkWarningContainer = Color(0xFF451A03);
  static const darkOnWarningContainer = Color(0xFFFBBF24);
  static const darkSuccess = Color(0xFF10B981);
  static const darkOnSuccess = Color(0xFF111827);
  static const darkSuccessContainer = Color(0xFF14532D);
  static const darkOnSuccessContainer = Color(0xFF4ADE80);
  static const darkInfo = Color(0xFF60A5FA);
  static const darkOnInfo = Color(0xFF111827);
  static const darkInfoContainer = Color(0xFF083344);
  static const darkOnInfoContainer = Color(0xFF67E8F9);
  static const darkLink = Color(0xFF60A5FA);
  static const darkLinkHover = Color(0xFF3B82F6);
  static const darkPanelBg = Color(0xFF111827);
  static const darkSectionHeaderBg = Color(0xFF1F2937);
  static const darkTextTertiary = Color(0xFF9CA3AF);
  static const darkPrimaryBg = Color(0xFF122E35);
}

/// The two dashboard themes, built from [TercenTokens]. Black (Tercen's
/// dark theme) is the default (see [ThemeController]): this is an
/// operations console, usually left open on a second screen.
class DashboardTheme {
  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        scheme: const ColorScheme(
          brightness: Brightness.dark,
          primary: TercenTokens.darkPrimary,
          onPrimary: TercenTokens.darkOnPrimary,
          primaryContainer: TercenTokens.darkPrimaryContainer,
          onPrimaryContainer: TercenTokens.darkOnPrimaryContainer,
          secondary: TercenTokens.darkSecondary,
          onSecondary: TercenTokens.darkOnSecondary,
          secondaryContainer: TercenTokens.darkSecondaryContainer,
          onSecondaryContainer: TercenTokens.darkOnSecondaryContainer,
          tertiary: TercenTokens.darkTertiary,
          onTertiary: TercenTokens.darkOnTertiary,
          tertiaryContainer: TercenTokens.darkTertiaryContainer,
          onTertiaryContainer: TercenTokens.darkOnTertiaryContainer,
          error: TercenTokens.darkError,
          onError: TercenTokens.darkOnError,
          errorContainer: TercenTokens.darkErrorContainer,
          onErrorContainer: TercenTokens.darkOnErrorContainer,
          surface: TercenTokens.darkSurface,
          onSurface: TercenTokens.darkOnSurface,
          onSurfaceVariant: TercenTokens.darkOnSurfaceVariant,
          surfaceContainerLowest: TercenTokens.darkSurfaceContainerLowest,
          surfaceContainerLow: TercenTokens.darkSurfaceContainerLow,
          surfaceContainer: TercenTokens.darkSurfaceContainer,
          surfaceContainerHigh: TercenTokens.darkSurfaceContainerHigh,
          surfaceContainerHighest: TercenTokens.darkSurfaceContainerHighest,
          outline: TercenTokens.darkOutline,
          outlineVariant: TercenTokens.darkOutlineVariant,
          inverseSurface: TercenTokens.darkInverseSurface,
          onInverseSurface: TercenTokens.darkOnInverseSurface,
          inversePrimary: TercenTokens.darkInversePrimary,
          scrim: TercenTokens.darkScrim,
          shadow: TercenTokens.darkShadow,
          surfaceTint: Colors.transparent,
        ),
        background: TercenTokens.darkBackground,
        panel: TercenTokens.darkPanelBg,
        muted: TercenTokens.darkOnSurfaceMuted,
        // visual-style-dark Table Row: hover neutral-800, selected
        // primary-dark-surface.
        rowHover: TercenTokens.darkSurfaceContainer,
        rowSelected: TercenTokens.darkPrimaryBg,
        colors: DashboardColors.dark,
      );

  static ThemeData get light => _build(
        brightness: Brightness.light,
        scheme: const ColorScheme(
          brightness: Brightness.light,
          primary: TercenTokens.lightPrimary,
          onPrimary: TercenTokens.lightOnPrimary,
          primaryContainer: TercenTokens.lightPrimaryContainer,
          onPrimaryContainer: TercenTokens.lightOnPrimaryContainer,
          secondary: TercenTokens.lightSecondary,
          onSecondary: TercenTokens.lightOnSecondary,
          secondaryContainer: TercenTokens.lightSecondaryContainer,
          onSecondaryContainer: TercenTokens.lightOnSecondaryContainer,
          tertiary: TercenTokens.lightTertiary,
          onTertiary: TercenTokens.lightOnTertiary,
          tertiaryContainer: TercenTokens.lightTertiaryContainer,
          onTertiaryContainer: TercenTokens.lightOnTertiaryContainer,
          error: TercenTokens.lightError,
          onError: TercenTokens.lightOnError,
          errorContainer: TercenTokens.lightErrorContainer,
          onErrorContainer: TercenTokens.lightOnErrorContainer,
          surface: TercenTokens.lightSurface,
          onSurface: TercenTokens.lightOnSurface,
          onSurfaceVariant: TercenTokens.lightOnSurfaceVariant,
          surfaceContainerLowest: TercenTokens.lightSurfaceContainerLowest,
          surfaceContainerLow: TercenTokens.lightSurfaceContainerLow,
          surfaceContainer: TercenTokens.lightSurfaceContainer,
          surfaceContainerHigh: TercenTokens.lightSurfaceContainerHigh,
          surfaceContainerHighest: TercenTokens.lightSurfaceContainerHighest,
          outline: TercenTokens.lightOutline,
          outlineVariant: TercenTokens.lightOutlineVariant,
          inverseSurface: TercenTokens.lightInverseSurface,
          onInverseSurface: TercenTokens.lightOnInverseSurface,
          inversePrimary: TercenTokens.lightInversePrimary,
          scrim: TercenTokens.lightScrim,
          shadow: TercenTokens.lightShadow,
          surfaceTint: Colors.transparent,
        ),
        background: TercenTokens.lightBackground,
        panel: TercenTokens.lightPanelBg,
        muted: TercenTokens.lightOnSurfaceMuted,
        // visual-style-light Table Row: hover neutral-50, selected
        // primary-bg.
        rowHover: TercenTokens.lightSurfaceContainerLow,
        rowSelected: TercenTokens.lightPrimaryBg,
        colors: DashboardColors.light,
      );

  /// [background] is the page behind the surfaces, [panel] the left rail,
  /// [muted] the caption ink and [rowHover] / [rowSelected] the table-row
  /// states: tokens with no ColorScheme slot.
  static const _font = TercenTokens.fontFamily;

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
    required Color background,
    required Color panel,
    required Color muted,
    required Color rowHover,
    required Color rowSelected,
    required DashboardColors colors,
  }) {
    final ink = scheme.onSurface;
    final outline = scheme.outline;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: TercenTokens.fontFamily,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      dividerColor: scheme.outlineVariant,
      dividerTheme: DividerThemeData(
          color: scheme.outlineVariant, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: panel,
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.primary, size: 22),
        unselectedIconTheme: IconThemeData(color: muted, size: 22),
        selectedLabelTextStyle: TextStyle(
            fontFamily: _font,
            color: scheme.primary,
            fontSize: 11.5,
            fontWeight: FontWeight.w600),
        unselectedLabelTextStyle:
            TextStyle(fontFamily: _font, color: muted, fontSize: 11.5),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(scheme.surfaceContainerLow),
        // Table Row: rows sit on the surface, not on the page ground.
        dataRowColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return rowSelected;
          if (states.contains(WidgetState.hovered)) return rowHover;
          return scheme.surface;
        }),
        headingTextStyle: TextStyle(
          fontFamily: _font,
          color: scheme.onSurfaceVariant,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
        dataTextStyle: TextStyle(
            fontFamily: _font, color: scheme.onSurfaceVariant, fontSize: 13.5),
        dividerThickness: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: outline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: scheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: scheme.primary),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: scheme.error),
        ),
        hintStyle: TextStyle(fontFamily: _font, color: muted, fontSize: 13),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle:
            TextStyle(fontFamily: _font, color: scheme.onInverseSurface),
        behavior: SnackBarBehavior.floating,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: TextStyle(
            fontFamily: _font, color: scheme.onInverseSurface, fontSize: 12),
      ),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      textTheme: Typography.material2021(
        platform: TargetPlatform.linux,
      )
          .black
          .apply(fontFamily: _font, bodyColor: ink, displayColor: ink)
          .copyWith(
            headlineSmall: TextStyle(
                color: ink,
                fontSize: 21,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2),
            titleMedium: TextStyle(
                color: ink, fontSize: 15.5, fontWeight: FontWeight.w600),
            titleSmall: TextStyle(
                color: ink, fontSize: 13.5, fontWeight: FontWeight.w600),
            bodyMedium: TextStyle(color: ink, fontSize: 13.5),
            bodySmall: TextStyle(color: muted, fontSize: 12.5),
            labelSmall: TextStyle(
                color: muted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7),
          ),
      extensions: [colors],
    );
  }
}

/// Holds the selected theme. Defaults to black and remembers the choice
/// per browser (localStorage); storage failures degrade to the default.
class ThemeController extends ValueNotifier<ThemeMode> {
  static const _storageKey = 'tercen.dashboard.theme';

  ThemeController() : super(ThemeMode.dark) {
    // An explicit ?theme= wins (shareable links, embedding), then the
    // remembered choice; black remains the default.
    final requested = platform.readUrlParam('theme');
    final stored =
        requested.isNotEmpty ? requested : platform.readSetting(_storageKey);
    if (stored == 'light') value = ThemeMode.light;
    if (stored == 'dark') value = ThemeMode.dark;
  }

  bool get isDark => value == ThemeMode.dark;

  void toggle() {
    value = isDark ? ThemeMode.light : ThemeMode.dark;
    final name = isDark ? 'dark' : 'light';
    platform.writeSetting(_storageKey, name);
    platform.setUrlParam('theme', name);
  }
}
