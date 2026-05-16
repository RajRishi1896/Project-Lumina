import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/lumina_colors.dart';

class LuminaTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: LuminaColors.primaryDeepBlue,
        surface: LuminaColors.surface,
        primary: LuminaColors.primaryDeepBlue,
        secondary: LuminaColors.academicTeal,
        tertiary: LuminaColors.saffron,
        onSurface: LuminaColors.onSurface,
        outline: LuminaColors.outline,
      ),
      scaffoldBackgroundColor: LuminaColors.surface,
      textTheme: GoogleFonts.atkinsonHyperlegibleTextTheme().copyWith(
        displayLarge: GoogleFonts.atkinsonHyperlegible(
          fontSize: 40,
          fontWeight: FontWeight.w800,
          height: 1.2,
          letterSpacing: -0.02,
          color: LuminaColors.onSurface,
        ),
        headlineMedium: GoogleFonts.atkinsonHyperlegible(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          height: 1.3,
          color: LuminaColors.onSurface,
        ),
        bodyLarge: GoogleFonts.atkinsonHyperlegible(
          fontSize: 18,
          fontWeight: FontWeight.w400,
          height: 1.6,
          color: LuminaColors.onSurface,
        ),
        bodyMedium: GoogleFonts.atkinsonHyperlegible(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          height: 1.6,
          color: LuminaColors.onSurface,
        ),
        labelLarge: GoogleFonts.atkinsonHyperlegible(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: LuminaColors.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: LuminaColors.outline, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: LuminaColors.primaryDeepBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
          textStyle: GoogleFonts.atkinsonHyperlegible(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: LuminaColors.outline, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: LuminaColors.outline, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: LuminaColors.primaryDeepBlue, width: 2),
        ),
        labelStyle: GoogleFonts.atkinsonHyperlegible(
          color: LuminaColors.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
