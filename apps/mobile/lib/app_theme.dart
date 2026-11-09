import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const brandRed = Color(0xFFD71920);
const ink = Color(0xFF0B1C30);
const canvas = Color(0xFFF8F9FF);
const muted = Color(0xFF5F5E5E);
const accentRed = Color(0xFFFF6268);
const softRed = Color(0xFFFFF1F2);
const neutralSurface = Color(0xFFEFF4FF);
const border = Color(0xFFE7EBF2);
const onDarkMuted = Color(0xFFD3D3D3);
const onDarkSubtle = Color(0xFFB3B3B3);
const darkTrack = Color(0xFF373737);
const bufferedTrack = Color(0xFFBDBDBD);

ThemeData fitnessTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'Inter',
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
      fontFamily: 'Inter',
      color: ink,
      fontSize: 17,
      fontWeight: FontWeight.w700,
    ),
  ),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontFamily: 'SpaceGrotesk',
      fontSize: 32,
      height: 1.12,
      fontWeight: FontWeight.w800,
      color: ink,
      letterSpacing: -1.2,
    ),
    headlineMedium: TextStyle(
      fontFamily: 'SpaceGrotesk',
      fontSize: 26,
      fontWeight: FontWeight.w800,
      color: ink,
      letterSpacing: -.7,
    ),
    titleLarge: TextStyle(
      fontFamily: 'SpaceGrotesk',
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
    elevation: .5,
    shadowColor: const Color(0x140B1C30),
    margin: const EdgeInsets.symmetric(vertical: 5),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: Color(0xFFE7EBF2)),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFE7EBF2)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: brandRed, width: 2),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 52),
      textStyle: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
      shape: const StadiumBorder(),
    ),
  ),
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    indicatorColor: softRed,
    height: 72,
    iconTheme: WidgetStateProperty.resolveWith(
      (states) => IconThemeData(
        color: states.contains(WidgetState.selected) ? brandRed : muted,
      ),
    ),
    labelTextStyle: WidgetStateProperty.resolveWith(
      (states) => TextStyle(
        fontFamily: 'Inter',
        fontSize: 11,
        fontWeight: states.contains(WidgetState.selected)
            ? FontWeight.w800
            : FontWeight.w500,
        color: states.contains(WidgetState.selected) ? brandRed : muted,
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
    contentTextStyle: TextStyle(fontFamily: 'Inter', color: Colors.white),
    actionTextColor: accentRed,
  ),
  textSelectionTheme: const TextSelectionThemeData(
    cursorColor: brandRed,
    selectionColor: Color(0xFFFFDADC),
    selectionHandleColor: brandRed,
  ),
  dividerTheme: const DividerThemeData(color: Color(0xFFE7EBF2), thickness: 1),
);

bool _fontLicensesRegistered = false;
void registerFitnessFontLicenses() {
  if (_fontLicensesRegistered) return;
  _fontLicensesRegistered = true;
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Inter',
    ], await rootBundle.loadString('assets/fonts/Inter-OFL.txt'));
    yield LicenseEntryWithLineBreaks([
      'Space Grotesk',
    ], await rootBundle.loadString('assets/fonts/SpaceGrotesk-OFL.txt'));
  });
}
