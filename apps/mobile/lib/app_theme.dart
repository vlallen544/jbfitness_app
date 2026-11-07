import 'package:flutter/material.dart';

const forest = Color(0xFF245E48);
const ink = Color(0xFF172D2C);
const canvas = Color(0xFFF7F8F5);
const muted = Color(0xFF657571);
const lime = Color(0xFFDDF59C);

ThemeData fitnessTheme() => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: forest,
    primary: forest,
    onPrimary: Colors.white,
    surface: Colors.white,
    onSurface: ink,
  ),
  scaffoldBackgroundColor: canvas,
  appBarTheme: const AppBarTheme(
    backgroundColor: canvas,
    foregroundColor: ink,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    titleTextStyle: TextStyle(
      color: ink,
      fontSize: 17,
      fontWeight: FontWeight.w700,
    ),
  ),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontSize: 32,
      height: 1.12,
      fontWeight: FontWeight.w800,
      color: ink,
      letterSpacing: -1.2,
    ),
    headlineMedium: TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w800,
      color: ink,
      letterSpacing: -.7,
    ),
    titleLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: ink,
      letterSpacing: -.4,
    ),
    bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: ink),
    bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: ink),
    bodySmall: TextStyle(fontSize: 12, height: 1.45, color: muted),
  ),
  cardTheme: CardThemeData(
    clipBehavior: Clip.antiAlias,
    color: Colors.white,
    elevation: 0,
    margin: const EdgeInsets.symmetric(vertical: 5),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: const BorderSide(color: Color(0xFFE3E9E3)),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFDCE4DE)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: forest, width: 2),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 52),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  ),
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    indicatorColor: lime,
    height: 76,
    labelTextStyle: WidgetStateProperty.resolveWith(
      (states) => TextStyle(
        fontSize: 11,
        fontWeight: states.contains(WidgetState.selected)
            ? FontWeight.w800
            : FontWeight.w500,
        color: states.contains(WidgetState.selected) ? ink : muted,
      ),
    ),
  ),
  dividerTheme: const DividerThemeData(color: Color(0xFFE3E9E3), thickness: 1),
);
