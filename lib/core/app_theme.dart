import 'package:flutter/material.dart';

const syncBackground = Color(0xFF071827);
const syncBackgroundDeep = Color(0xFF05121E);
const syncSurface = Color(0xFF0C2135);
const syncSurfaceRaised = Color(0xFF102A43);
const syncBorder = Color(0xFF1B4060);
const syncAccent = Color(0xFF2F8CFF);
const syncAccentSoft = Color(0xFF6AAFFF);
const syncSuccess = Color(0xFF30D98B);

ThemeData buildSyncWatchTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: syncAccent,
    brightness: Brightness.dark,
    surface: syncSurface,
  ).copyWith(
    primary: syncAccent,
    secondary: syncAccentSoft,
    surface: syncSurface,
  );

  return ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: syncBackground,
    dividerColor: syncBorder.withValues(alpha: 0.55),
    cardColor: syncSurface,
    dialogTheme: DialogThemeData(
      backgroundColor: syncSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: syncBorder),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: syncAccent,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 46),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 44),
        side: const BorderSide(color: syncBorder),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 3,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF081B2C),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: syncBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: syncBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: syncAccent),
      ),
    ),
  );
}
