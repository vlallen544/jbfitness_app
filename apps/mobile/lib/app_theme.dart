import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const brandRed = Color(0xFFD71920);
const ink = Color(0xFF111111);
const canvas = Color(0xFFFFFFFF);
const muted = Color(0xFF636363);
const accentRed = Color(0xFFFF6268);
const softRed = Color(0xFFFFF1F2);
const neutralSurface = Color(0xFFF5F5F5);
const border = Color(0xFFE5E5E5);
const onDarkMuted = Color(0xFFD3D3D3);
const onDarkSubtle = Color(0xFFB3B3B3);
const darkTrack = Color(0xFF373737);
const bufferedTrack = Color(0xFFBDBDBD);

ThemeData fitnessTheme() => ThemeData(
  useMaterial3: true,
  colorScheme: const ColorScheme.light(
    primary: brandRed,
    onPrimary: Colors.white,
    primaryContainer: softRed,
    onPrimaryContainer: brandRed,
    secondary: ink,
    onSecondary: Colors.white,
    secondaryContainer: softRed,
    onSecondaryContainer: brandRed,
    tertiary: brandRed,
    onTertiary: Colors.white,
    tertiaryContainer: softRed,
    onTertiaryContainer: brandRed,
    error: Color(0xFFB91C1C),
    onError: Colors.white,
    errorContainer: softRed,
    onErrorContainer: Color(0xFF991B1B),
    surface: Colors.white,
    onSurface: ink,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: neutralSurface,
    surfaceContainer: Colors.white,
    surfaceContainerHigh: neutralSurface,
    surfaceContainerHighest: neutralSurface,
    onSurfaceVariant: muted,
    outline: Color(0xFF949494),
    outlineVariant: border,
    surfaceTint: Colors.transparent,
    inverseSurface: ink,
    onInverseSurface: Colors.white,
    inversePrimary: accentRed,
  ),
  scaffoldBackgroundColor: canvas,
  appBarTheme: const AppBarTheme(
    backgroundColor: canvas,
    foregroundColor: ink,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    systemOverlayStyle: SystemUiOverlayStyle.dark,
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
      side: const BorderSide(color: Color(0xFFE5E5E5)),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFE5E5E5)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: brandRed, width: 2),
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
    indicatorColor: brandRed,
    height: 76,
    iconTheme: WidgetStateProperty.resolveWith(
      (states) => IconThemeData(
        color: states.contains(WidgetState.selected) ? Colors.white : muted,
      ),
    ),
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
  progressIndicatorTheme: const ProgressIndicatorThemeData(
    color: brandRed,
    linearTrackColor: border,
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(foregroundColor: brandRed),
  ),
  snackBarTheme: const SnackBarThemeData(
    backgroundColor: ink,
    contentTextStyle: TextStyle(color: Colors.white),
    actionTextColor: accentRed,
  ),
  textSelectionTheme: const TextSelectionThemeData(
    cursorColor: brandRed,
    selectionColor: Color(0xFFFFDADC),
    selectionHandleColor: brandRed,
  ),
  dividerTheme: const DividerThemeData(color: Color(0xFFE5E5E5), thickness: 1),
);
