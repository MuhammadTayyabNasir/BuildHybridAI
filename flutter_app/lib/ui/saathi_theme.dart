import 'package:flutter/material.dart';

abstract final class SaathiColors {
  static const deepTeal = Color(0xFF103D44);
  static const teal = Color(0xFF126873);
  static const mint = Color(0xFFB9E7D4);
  static const ivory = Color(0xFFF8F6EF);
  static const ink = Color(0xFF17343A);
  static const mutedInk = Color(0xFF52656A);
  static const error = Color(0xFFA8333A);
}

ThemeData saathiTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final background = dark ? const Color(0xFF102528) : SaathiColors.ivory;
  final surface = dark ? const Color(0xFF19353A) : Colors.white;
  final foreground = dark ? SaathiColors.ivory : SaathiColors.ink;
  final primary = dark ? SaathiColors.mint : SaathiColors.deepTeal;
  final onPrimary = dark ? SaathiColors.deepTeal : Colors.white;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: primary,
    onPrimary: onPrimary,
    primaryContainer: dark ? const Color(0xFF27565C) : const Color(0xFFDBEFE5),
    onPrimaryContainer: foreground,
    secondary: dark ? const Color(0xFF8DD6C0) : SaathiColors.teal,
    onSecondary: dark ? SaathiColors.deepTeal : Colors.white,
    secondaryContainer: dark
        ? const Color(0xFF27565C)
        : const Color(0xFFDBEFE5),
    onSecondaryContainer: foreground,
    error: dark ? const Color(0xFFFFB4AB) : SaathiColors.error,
    onError: dark ? const Color(0xFF690005) : Colors.white,
    surface: surface,
    onSurface: foreground,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: foreground,
      centerTitle: false,
      elevation: 0,
    ),
    textTheme: TextTheme(
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: foreground,
        height: 1.18,
      ),
      titleLarge: TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w700,
        color: foreground,
      ),
      titleMedium: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: foreground,
      ),
      bodyLarge: TextStyle(fontSize: 16, color: foreground, height: 1.45),
      bodyMedium: TextStyle(fontSize: 14, color: foreground, height: 1.45),
      labelLarge: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: dark ? const Color(0xFF8AA7A9) : const Color(0xFF657C7F),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
  );
}
