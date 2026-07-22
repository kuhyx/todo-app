/// The app's design tokens: one identical palette shared across every one
/// of kuhy's apps (Flutter, web, Python/Tkinter alike) — see the
/// `unified-design-system` skill (`~/.claude/skills/unified-design-system/`)
/// for the frozen token table this file implements. Built from explicit
/// `ColorScheme`s, not `ColorScheme.fromSeed`, because the shared palette is
/// hand-picked, not algorithmically derived from one seed color.
library;

import 'package:flutter/material.dart';

/// Builds the app's light `ThemeData` from the shared token set.
ThemeData buildLightTheme() {
  const colorScheme = ColorScheme.light(
    surface: Color(0xFFF6F4F3), // paper
    surfaceContainerHighest: Color(0xFFFCFBFB), // paper-raised
    onSurface: Color(0xFF211D1B), // text-on-light (= ink)
    onSurfaceVariant: Color(0xFF70625B), // muted-on-light
    outline: Color(0xFFE0DAD7), // line-light
    primary: Color(0xFFB8862E), // accent
    onPrimary: Color(0xFF211D1B), // on-fill — filled surfaces use dark text
    // secondary/tertiary — the shared palette has one accent, not a
    // separate secondary hue, so these mirror primary. Without an explicit
    // value here, widgets that reach for secondaryContainer (e.g.
    // SegmentedButton's selected segment) silently fall back to Flutter's
    // stock Material teal — confirmed live on-device, not just in theory.
    secondary: Color(0xFFB8862E), // accent
    onSecondary: Color(0xFF211D1B), // on-fill
    secondaryContainer: Color(0xFFE0DAD7), // line-light
    onSecondaryContainer: Color(0xFFB8862E), // accent
    tertiary: Color(0xFFB8862E), // accent
    onTertiary: Color(0xFF211D1B), // on-fill
    tertiaryContainer: Color(0xFFE0DAD7), // line-light
    onTertiaryContainer: Color(0xFFB8862E), // accent
    error: Color(0xFFE2585F), // danger
    onError: Color(0xFF211D1B), // on-fill
  );
  return _buildTheme(colorScheme);
}

/// Builds the app's dark `ThemeData` from the shared token set.
ThemeData buildDarkTheme() {
  const colorScheme = ColorScheme.dark(
    surface: Color(0xFF211D1B), // ink
    surfaceContainerHighest: Color(0xFF38312E), // ink-raised-2
    surfaceContainerHigh: Color(0xFF2B2624), // ink-raised-1
    onSurface: Color(0xFFECEAE9), // text-on-dark
    onSurfaceVariant: Color(0xFFAAA09A), // muted-on-dark
    outline: Color(0xFF463E3A), // line-dark
    primary: Color(0xFFB8862E), // accent
    onPrimary: Color(0xFF211D1B), // on-fill
    secondary: Color(0xFFB8862E), // accent
    onSecondary: Color(0xFF211D1B), // on-fill
    secondaryContainer: Color(0xFF463E3A), // line-dark
    onSecondaryContainer: Color(0xFFB8862E), // accent
    tertiary: Color(0xFFB8862E), // accent
    onTertiary: Color(0xFF211D1B), // on-fill
    tertiaryContainer: Color(0xFF463E3A), // line-dark
    onTertiaryContainer: Color(0xFFB8862E), // accent
    error: Color(0xFFE2585F), // danger
    onError: Color(0xFF211D1B), // on-fill
  );
  return _buildTheme(colorScheme);
}

ThemeData _buildTheme(ColorScheme colorScheme) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colorScheme.surface,
    textTheme: const TextTheme(
      bodyLarge: TextStyle(fontSize: AppTextSize.body),
      bodyMedium: TextStyle(fontSize: AppTextSize.body),
      titleLarge: TextStyle(fontSize: AppTextSize.title),
      titleMedium: TextStyle(fontSize: AppTextSize.subtitle),
      labelMedium: TextStyle(fontSize: AppTextSize.label),
      labelSmall: TextStyle(fontSize: AppTextSize.caption),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: colorScheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: colorScheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outline,
      thickness: 1,
      space: AppSpacing.md,
    ),
  );
}

/// Shared spacing scale (4px base) — round any new value to one of these
/// instead of introducing an off-scale literal.
abstract final class AppSpacing {
  /// 4px.
  static const double xs = 4;

  /// 8px.
  static const double sm = 8;

  /// 16px.
  static const double md = 16;

  /// 24px.
  static const double lg = 24;

  /// 32px.
  static const double xl = 32;

  /// 48px.
  static const double xxl = 48;
}

/// Shared corner-radius scale. Nested radii should be `outer - gap`, not a
/// fixed constant — compute per instance per safe-design-rules rule 24.
abstract final class AppRadius {
  /// Buttons, inputs, chips.
  static const double sm = 8;

  /// Cards.
  static const double md = 12;

  /// Sheets, dialogs.
  static const double lg = 16;
}

/// Shared type scale (px). `body` is the floor for anything a user reads;
/// `label`/`caption` are for UI chrome only (timestamps, badges, tags).
abstract final class AppTextSize {
  /// 12px — chrome only.
  static const double caption = 12;

  /// 14px — chrome only.
  static const double label = 14;

  /// 16px — the floor for actual reading content.
  static const double body = 16;

  /// 20px.
  static const double subtitle = 20;

  /// 24px.
  static const double title = 24;

  /// 32px.
  static const double display = 32;
}

/// Prose/paragraph line-length cap (rule 21) — this app's desktop build is a
/// Chrome `--app` window that can be arbitrarily wide (potentially 4K), so
/// rendered/edited note text needs an explicit column width instead of
/// filling the whole viewport.
const double kProseMaxWidth = 640;
