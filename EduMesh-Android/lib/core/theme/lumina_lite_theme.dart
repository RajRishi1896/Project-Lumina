import 'package:flutter/material.dart';
import '../constants/lumina_colors.dart';
import '../constants/app_spacing.dart';

/// Provides the [ThemeData] definitions for the Lumina Lite light and dark themes.
class LuminaLiteTheme {
  /// The light theme configuration using Material 3 with a deep-navy primary palette.
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: LuminaColors.lightPrimary,
      scaffoldBackgroundColor: LuminaColors.lightSurface,
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: LuminaColors.lightPrimary,
        onPrimary: LuminaColors.onPrimary,
        primaryContainer: LuminaColors.lightPrimaryContainer,
        onPrimaryContainer: LuminaColors.lightOnPrimaryContainer,
        secondary: LuminaColors.lightSecondary,
        onSecondary: LuminaColors.onPrimary,
        secondaryContainer: LuminaColors.lightSecondaryContainer,
        onSecondaryContainer: LuminaColors.lightOnSecondaryContainer,
        tertiary: LuminaColors.lightTertiary,
        onTertiary: LuminaColors.onPrimary,
        tertiaryContainer: LuminaColors.lightTertiaryContainer,
        onTertiaryContainer: LuminaColors.lightOnTertiaryContainer,
        error: LuminaColors.lightError,
        onError: LuminaColors.onPrimary,
        errorContainer: LuminaColors.lightErrorContainer,
        onErrorContainer: LuminaColors.lightOnErrorContainer,
        surface: LuminaColors.lightSurface,
        onSurface: LuminaColors.lightOnSurface,
        surfaceContainerHighest: LuminaColors.lightSurfaceContainerHighest,
        onSurfaceVariant: LuminaColors.lightOnSurfaceVariant,
        outline: LuminaColors.lightOutline,
        outlineVariant: LuminaColors.lightOutlineVariant,
        inverseSurface: LuminaColors.lightInverseSurface,
        inversePrimary: LuminaColors.lightInversePrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: LuminaColors.lightPrimary,
        foregroundColor: LuminaColors.onPrimary,
        elevation: 0,
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(color: LuminaColors.lightPrimary, fontWeight: AppSpacing.weightStrong),
        bodyMedium: TextStyle(color: LuminaColors.lightOnSurface),
        bodySmall: TextStyle(color: LuminaColors.lightOnSurfaceVariant),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
        minVerticalPadding: AppSpacing.sm,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: LuminaColors.lightPrimary,
        unselectedLabelColor: LuminaColors.lightOnSurfaceVariant,
        indicatorColor: LuminaColors.lightPrimary,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: LuminaColors.lightPrimary,
          foregroundColor: LuminaColors.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: LuminaColors.lightOutlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: LuminaColors.lightOutlineVariant),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: LuminaColors.lightSurfaceContainerHighest,
        selectedItemColor: LuminaColors.academicTeal,
        unselectedItemColor: LuminaColors.lightOnSurfaceVariant,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: LuminaColors.lightOutlineVariant),
        ),
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }

  /// The dark theme configuration using Material 3 with a slate-based primary palette.
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: LuminaColors.darkInversePrimary,
      scaffoldBackgroundColor: LuminaColors.darkSurface,
      colorScheme: const ColorScheme(
        brightness: Brightness.dark,
        primary: LuminaColors.darkPrimary,
        onPrimary: LuminaColors.darkOnPrimary,
        primaryContainer: LuminaColors.darkPrimaryContainer,
        onPrimaryContainer: LuminaColors.darkOnPrimaryContainer,
        secondary: LuminaColors.darkSecondary,
        onSecondary: LuminaColors.darkOnSecondary,
        secondaryContainer: LuminaColors.darkSecondaryContainer,
        onSecondaryContainer: LuminaColors.darkOnSecondaryContainer,
        tertiary: LuminaColors.darkTertiary,
        onTertiary: LuminaColors.darkOnTertiary,
        tertiaryContainer: LuminaColors.darkTertiaryContainer,
        onTertiaryContainer: LuminaColors.darkOnTertiaryContainer,
        error: LuminaColors.darkError,
        onError: LuminaColors.darkOnError,
        errorContainer: LuminaColors.darkErrorContainer,
        onErrorContainer: LuminaColors.darkOnErrorContainer,
        surface: LuminaColors.darkSurface,
        onSurface: LuminaColors.darkOnSurface,
        surfaceContainerHighest: LuminaColors.darkSurfaceContainerHighest,
        onSurfaceVariant: LuminaColors.darkOnSurfaceVariant,
        outline: LuminaColors.darkOutline,
        outlineVariant: LuminaColors.darkOutlineVariant,
        inverseSurface: LuminaColors.darkInverseSurface,
        inversePrimary: LuminaColors.darkInversePrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: LuminaColors.darkSurface,
        foregroundColor: LuminaColors.darkOnSurface,
        elevation: 0,
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(color: LuminaColors.darkOnSurface, fontWeight: AppSpacing.weightStrong),
        bodyMedium: TextStyle(color: LuminaColors.darkOnSurface),
        bodySmall: TextStyle(color: LuminaColors.darkOnSurfaceVariant),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
        minVerticalPadding: AppSpacing.sm,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: LuminaColors.darkOnSurface,
        unselectedLabelColor: LuminaColors.darkOnSurfaceVariant,
        indicatorColor: LuminaColors.darkPrimary,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: LuminaColors.darkPrimary,
          foregroundColor: LuminaColors.darkOnPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: LuminaColors.darkOutlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: LuminaColors.darkOutlineVariant),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: LuminaColors.darkSurfaceContainerHighest,
        selectedItemColor: LuminaColors.academicTeal,
        unselectedItemColor: LuminaColors.darkOutline,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: LuminaColors.darkOutlineVariant),
        ),
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }
}
