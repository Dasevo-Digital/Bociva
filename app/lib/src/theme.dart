import 'package:flutter/material.dart';

abstract final class BocivaColors {
  static const pine = Color(0xFF24574A);
  static const mint = Color(0xFFBFE3D0);
  static const apricot = Color(0xFFEE9153);
  static const paper = Color(0xFFF6F2E9);
  static const ink = Color(0xFF17231F);
  static const protein = Color(0xFFB4506F);
  static const carbs = Color(0xFFD99A26);
  static const fat = Color(0xFF3D8AA1);
  static const water = Color(0xFF3E8EDE);
}

ThemeData bocivaTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: BocivaColors.pine,
        brightness: brightness,
      ).copyWith(
        primary: dark ? BocivaColors.mint : BocivaColors.pine,
        onPrimary: dark ? BocivaColors.ink : Colors.white,
        tertiary: BocivaColors.apricot,
        surface: dark ? const Color(0xFF111B18) : BocivaColors.paper,
      );
  return ThemeData(
    colorScheme: scheme,
    fontFamily: 'Nunito',
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Nunito',
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      color: dark ? const Color(0xFF1A2925) : Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF1A2925) : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        textStyle: const TextStyle(
          fontFamily: 'Nunito',
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
