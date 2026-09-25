import 'package:flutter/material.dart';

const syncBackground = Color(0xFF071827);
const syncBackgroundDeep = Color(0xFF05121E);
const syncSurface = Color(0xFF0C2135);
const syncSurfaceRaised = Color(0xFF102A43);
const syncBorder = Color(0xFF1B4060);
const syncAccent = Color(0xFF2F8CFF);
const syncAccentSoft = Color(0xFF6AAFFF);
const syncSuccess = Color(0xFF30D98B);

const syncLightBackground = Color(0xFFE7EEF4);
const syncLightBackgroundDeep = Color(0xFFDCE6EE);
const syncLightSurface = Color(0xFFF1F5F8);
const syncLightSurfaceRaised = Color(0xFFF7FAFC);
const syncLightBorder = Color(0xFFB9C9D6);
const syncLightText = Color(0xFF1A2B3A);
const syncLightTextSecondary = Color(0xFF617386);

ThemeData buildSyncWatchTheme(Brightness brightness) {
  final isLight = brightness == Brightness.light;
  final background = isLight ? syncLightBackground : syncBackground;
  final surface = isLight ? syncLightSurface : syncSurface;
  final border = isLight ? syncLightBorder : syncBorder;
  final text = isLight ? syncLightText : Colors.white;
  final secondaryText =
      isLight ? syncLightTextSecondary : Colors.white70;
  final inputFill =
      isLight ? syncLightSurfaceRaised : const Color(0xFF081B2C);

  final scheme = ColorScheme.fromSeed(
    seedColor: syncAccent,
    brightness: brightness,
    surface: surface,
  ).copyWith(
    primary: syncAccent,
    secondary: syncAccentSoft,
    surface: surface,
    onSurface: text,
  );

  return ThemeData(
    brightness: brightness,
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    dividerColor: border.withValues(alpha: 0.72),
    cardColor: surface,
    textTheme: ThemeData(brightness: brightness)
        .textTheme
        .apply(
          bodyColor: text,
          displayColor: text,
        ),
    iconTheme: IconThemeData(color: secondaryText),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: border),
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
        foregroundColor: text,
        minimumSize: const Size(0, 44),
        side: BorderSide(color: border),
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
      fillColor: inputFill,
      labelStyle: TextStyle(color: secondaryText),
      hintStyle: TextStyle(color: secondaryText),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: syncAccent),
      ),
    ),
  );
}
