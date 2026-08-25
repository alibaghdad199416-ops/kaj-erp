import 'package:flutter/material.dart';

/// Signature typography scale shared by every KAJ workspace screen.
abstract final class KajTypography {
  static const String primaryFamily = 'Cairo';
  static const List<String> fallbackFamilies = <String>[
    'IBM Plex Sans Arabic',
    'Noto Sans Arabic',
    'Segoe UI',
    'Tahoma',
    'Arial',
    'sans-serif',
  ];

  static TextTheme theme(Color foreground, Color muted) => TextTheme(
    displayLarge: TextStyle(
      color: foreground,
      fontSize: 48,
      height: 1.08,
      fontWeight: FontWeight.w900,
      letterSpacing: -1.4,
    ),
    displayMedium: TextStyle(
      color: foreground,
      fontSize: 40,
      height: 1.10,
      fontWeight: FontWeight.w900,
      letterSpacing: -1.05,
    ),
    displaySmall: TextStyle(
      color: foreground,
      fontSize: 34,
      height: 1.12,
      fontWeight: FontWeight.w900,
      letterSpacing: -.8,
    ),
    headlineLarge: TextStyle(
      color: foreground,
      fontSize: 30,
      height: 1.16,
      fontWeight: FontWeight.w900,
      letterSpacing: -.62,
    ),
    headlineMedium: TextStyle(
      color: foreground,
      fontSize: 25,
      height: 1.18,
      fontWeight: FontWeight.w900,
      letterSpacing: -.45,
    ),
    headlineSmall: TextStyle(
      color: foreground,
      fontSize: 21,
      height: 1.20,
      fontWeight: FontWeight.w800,
      letterSpacing: -.3,
    ),
    titleLarge: TextStyle(
      color: foreground,
      fontSize: 18,
      height: 1.24,
      fontWeight: FontWeight.w800,
    ),
    titleMedium: TextStyle(
      color: foreground,
      fontSize: 15,
      height: 1.30,
      fontWeight: FontWeight.w800,
    ),
    titleSmall: TextStyle(
      color: foreground,
      fontSize: 13,
      height: 1.32,
      fontWeight: FontWeight.w700,
    ),
    bodyLarge: TextStyle(
      color: foreground,
      fontSize: 15,
      height: 1.52,
      fontWeight: FontWeight.w500,
    ),
    bodyMedium: TextStyle(
      color: foreground,
      fontSize: 13.5,
      height: 1.48,
      fontWeight: FontWeight.w500,
    ),
    bodySmall: TextStyle(
      color: muted,
      fontSize: 12,
      height: 1.44,
      fontWeight: FontWeight.w500,
    ),
    labelLarge: TextStyle(
      color: foreground,
      fontSize: 13,
      height: 1.20,
      fontWeight: FontWeight.w800,
    ),
    labelMedium: TextStyle(
      color: muted,
      fontSize: 11.5,
      height: 1.20,
      fontWeight: FontWeight.w700,
    ),
    labelSmall: TextStyle(
      color: muted,
      fontSize: 10.5,
      height: 1.18,
      fontWeight: FontWeight.w700,
      letterSpacing: .10,
    ),
  );

  static TextStyle dataNumber(Color color, {double size = 22}) => TextStyle(
    color: color,
    fontSize: size,
    height: 1.0,
    fontWeight: FontWeight.w900,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );
}
