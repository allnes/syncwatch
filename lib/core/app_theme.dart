import 'package:flutter/material.dart';

ThemeData buildSyncWatchTheme() {
  const accent = Color(0xFF4C8DFF);
  const background = Color(0xFF090D14);
  const surface = Color(0xFF101722);

  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.dark,
    surface: surface,
  );

  return ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    dividerColor: Colors.white12,
    sliderTheme: const SliderThemeData(
      trackHeight: 3,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.04),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
  );
}
