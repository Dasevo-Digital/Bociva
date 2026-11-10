import 'package:flutter/material.dart';

abstract final class BocivaColors {
  // Aus dem Markenbild: Schriftzug, Blatt, Apfel.
  static const forest = Color(0xFF1C6631);
  static const forestDeep = Color(0xFF0E4A1E);
  static const leaf = Color(0xFF6DB33F);
  static const mint = Color(0xFFB8E3B0);
  static const coral = Color(0xFFF2735A);
  static const paper = Color(0xFFFBF7F1);
  static const ink = Color(0xFF14211A);
  static const protein = Color(0xFFB4506F);
  static const carbs = Color(0xFFD99A26);
  static const fat = Color(0xFF3D8AA1);
  static const water = Color(0xFF3E8EDE);
}

ThemeData bocivaTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: BocivaColors.forest,
        brightness: brightness,
      ).copyWith(
        primary: dark ? BocivaColors.mint : BocivaColors.forest,
        onPrimary: dark ? BocivaColors.ink : Colors.white,
        tertiary: BocivaColors.coral,
        surface: dark ? const Color(0xFF101A14) : BocivaColors.paper,
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
      color: dark ? const Color(0xFF19271F) : Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF19271F) : Colors.white,
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
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF16231B) : Colors.white,
      indicatorColor: dark
          ? BocivaColors.forest
          : BocivaColors.leaf.withValues(alpha: 0.28),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: dark ? const Color(0xFF16231B) : Colors.white,
      indicatorColor: dark
          ? BocivaColors.forest
          : BocivaColors.leaf.withValues(alpha: 0.28),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: BocivaColors.coral,
      foregroundColor: Colors.white,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
