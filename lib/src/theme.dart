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
  });

  static const dark = DashboardColors(
    okBg: Color(0xFF11291E),
    okFg: Color(0xFF6FCEA0),
    warnBg: Color(0xFF2C2210),
    warnFg: Color(0xFFE3B45B),
    badBg: Color(0xFF2E1614),
    badFg: Color(0xFFEE9188),
    infoBg: Color(0xFF0E2831),
    infoFg: Color(0xFF5FCEE2),
    neutralBg: Color(0xFF1A1D21),
    neutralFg: Color(0xFF9BA3AB),
  );

  static const light = DashboardColors(
    okBg: Color(0xFFE2F3EA),
    okFg: Color(0xFF186A45),
    warnBg: Color(0xFFF8EEDD),
    warnFg: Color(0xFF8A5E07),
    badBg: Color(0xFFFAE8E6),
    badFg: Color(0xFFA33227),
    infoBg: Color(0xFFDCEEFB),
    infoFg: Color(0xFF0B5C8A),
    neutralBg: Color(0xFFEDF1F3),
    neutralFg: Color(0xFF5B6C78),
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
    );
  }
}

/// The two dashboard themes. Black is the default (see [ThemeController]):
/// this is an operations console, usually left open on a second screen.
class DashboardTheme {
  // Black theme — true black ground, panels lifted just enough to read as
  // surfaces, cyan accent carried over from the specification document.
  static const _darkGround = Color(0xFF000000);
  static const _darkSurface = Color(0xFF101215);
  static const _darkSurfaceHigh = Color(0xFF181B1F);
  static const _darkOutline = Color(0xFF2A2E33);
  static const _darkInk = Color(0xFFE6E9EC);
  static const _darkMuted = Color(0xFF98A2AB);
  static const _darkAccent = Color(0xFF39C0D8);
  static const _darkError = Color(0xFFEE9188);

  // White theme — paper ground with a slightly cool grey, deep teal accent.
  static const _lightGround = Color(0xFFFFFFFF);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightSurfaceHigh = Color(0xFFF2F5F7);
  static const _lightOutline = Color(0xFFDDE4E8);
  static const _lightInk = Color(0xFF14181B);
  static const _lightMuted = Color(0xFF5B6C78);
  static const _lightAccent = Color(0xFF0E7490);
  static const _lightError = Color(0xFFA33227);

  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        ground: _darkGround,
        surface: _darkSurface,
        surfaceHigh: _darkSurfaceHigh,
        outline: _darkOutline,
        ink: _darkInk,
        muted: _darkMuted,
        accent: _darkAccent,
        error: _darkError,
        colors: DashboardColors.dark,
      );

  static ThemeData get light => _build(
        brightness: Brightness.light,
        ground: _lightGround,
        surface: _lightSurface,
        surfaceHigh: _lightSurfaceHigh,
        outline: _lightOutline,
        ink: _lightInk,
        muted: _lightMuted,
        accent: _lightAccent,
        error: _lightError,
        colors: DashboardColors.light,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color ground,
    required Color surface,
    required Color surfaceHigh,
    required Color outline,
    required Color ink,
    required Color muted,
    required Color accent,
    required Color error,
    required DashboardColors colors,
  }) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: isDark ? const Color(0xFF04181D) : Colors.white,
      secondary: accent,
      onSecondary: isDark ? const Color(0xFF04181D) : Colors.white,
      error: error,
      onError: isDark ? const Color(0xFF2E1614) : Colors.white,
      surface: surface,
      onSurface: ink,
      onSurfaceVariant: muted,
      surfaceContainerHighest: surfaceHigh,
      outline: outline,
      outlineVariant: outline,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: ground,
      canvasColor: ground,
      dividerColor: outline,
      dividerTheme: DividerThemeData(color: outline, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: outline),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isDark ? const Color(0xFF08090B) : surfaceHigh,
        indicatorColor: accent.withValues(alpha: isDark ? 0.18 : 0.14),
        selectedIconTheme: IconThemeData(color: accent, size: 22),
        unselectedIconTheme: IconThemeData(color: muted, size: 22),
        selectedLabelTextStyle: TextStyle(
            color: accent, fontSize: 11.5, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle: TextStyle(color: muted, fontSize: 11.5),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(surfaceHigh),
        headingTextStyle: TextStyle(
          color: muted,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
        dataTextStyle: TextStyle(color: ink, fontSize: 13.5),
        dividerThickness: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: outline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: isDark ? const Color(0xFF0B0D0F) : surfaceHigh,
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
          borderSide: BorderSide(color: accent),
        ),
        hintStyle: TextStyle(color: muted, fontSize: 13),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: TextStyle(color: ink),
        behavior: SnackBarBehavior.floating,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF23272C) : const Color(0xFF14181B),
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      iconTheme: IconThemeData(color: muted),
      textTheme: Typography.material2021(
        platform: TargetPlatform.linux,
      ).black.apply(bodyColor: ink, displayColor: ink).copyWith(
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
    final stored = platform.readSetting(_storageKey);
    if (stored == 'light') value = ThemeMode.light;
    if (stored == 'dark') value = ThemeMode.dark;
  }

  bool get isDark => value == ThemeMode.dark;

  void toggle() {
    value = isDark ? ThemeMode.light : ThemeMode.dark;
    platform.writeSetting(_storageKey, isDark ? 'dark' : 'light');
  }
}
