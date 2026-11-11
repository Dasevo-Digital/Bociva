import 'package:flutter/material.dart';

abstract final class BocivaColors {
  // Aus Maskottchen und App-Icon: Blätter, Schriftzug, Apfel, Gesicht.
  static const forest = Color(0xFF17602F);
  static const forestDeep = Color(0xFF0B4A1F);

  /// Kräftiges Grün der Icon-Kachel; mit weißer Schrift 4,7:1.
  static const green = Color(0xFF14853A);
  static const leaf = Color(0xFF8CCB3A);
  static const lime = Color(0xFFBCEB8C);
  static const mint = Color(0xFFB8E3B0);
  static const coral = Color(0xFFF47B5C);

  /// Für Flächen mit weißer Schrift (Kontrast 4,7:1 statt 2,9:1).
  static const coralDeep = Color(0xFFC94A32);
  static const apple = Color(0xFFF2554E);
  static const peach = Color(0xFFFDE4D8);
  static const cream = Color(0xFFF7EBDF);
  static const wheat = Color(0xFFF2A93B);
  static const paper = Color(0xFFFFF8F1);
  static const ink = Color(0xFF14211A);
  static const water = Color(0xFF3E8EDE);

  // Nährstoffe wie auf dem Telefon des Maskottchens: Hantel, Ähre, Tropfen.
  static const protein = Color(0xFF3FA34D);
  static const carbs = wheat;
  static const fat = coral;

  /// Hellere Töne für die dunkelgrüne Tageskarte.
  static const proteinOnGreen = lime;
  static const carbsOnGreen = Color(0xFFFFCF73);
  static const fatOnGreen = Color(0xFFFFAD96);

  /// Hintergrund der Karten.
  static Color card(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF19271F) : Colors.white;
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
        secondary: dark ? BocivaColors.lime : BocivaColors.green,
        secondaryContainer: dark
            ? const Color(0xFF24452C)
            : BocivaColors.lime.withValues(alpha: 0.55),
        onSecondaryContainer: dark
            ? BocivaColors.lime
            : BocivaColors.forestDeep,
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
      color: BocivaColors.card(brightness),
      elevation: dark ? 0 : 1.5,
      shadowColor: const Color(0x332E6B3A),
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
          : BocivaColors.lime.withValues(alpha: 0.7),
      elevation: 3,
      shadowColor: const Color(0x332E6B3A),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: dark ? const Color(0xFF16231B) : Colors.white,
      indicatorColor: dark
          ? BocivaColors.forest
          : BocivaColors.lime.withValues(alpha: 0.7),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide.none,
      backgroundColor: dark
          ? const Color(0xFF223529)
          : BocivaColors.cream.withValues(alpha: 0.8),
      shape: const StadiumBorder(),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: BocivaColors.coralDeep,
      foregroundColor: Colors.white,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
