import 'package:flutter/material.dart';
import '../constants/app_spacing.dart';

/// A palette of core brand colours used in the Lumina Lite theme.
class LuminaLiteColors {
  /// A deep navy blue used for primary elements.
  static const Color deepNavy = Color(0xFF1A365D);

  /// A teal accent used for secondary interactive elements.
  static const Color teal = Color(0xFF0D9488);

  /// A soft cream colour used for light mode backgrounds.
  static const Color softCream = Color(0xFFF9F9F7);

  /// A green colour for success states and indicators.
  static const Color successGreen = Color(0xFF16A34A);

  /// A red colour for error states and destructive actions.
  static const Color danger = Color(0xFFDC2626);
}

/// Provides the [ThemeData] definitions for the Lumina Lite light and dark themes.
class LuminaLiteTheme {
  /// The light theme configuration using Material 3 with a deep-navy primary palette.
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: LuminaLiteColors.deepNavy,
      scaffoldBackgroundColor: const Color(0xFFF9F9FF),
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: Color(0xFF002045),
        onPrimary: Color(0xFFFFFFFF),
        primaryContainer: Color(0xFFD6E3FF),
        onPrimaryContainer: Color(0xFF001B3C),
        secondary: Color(0xFF13696A),
        onSecondary: Color(0xFFFFFFFF),
        secondaryContainer: Color(0xFFA2EDED),
        onSecondaryContainer: Color(0xFF002020),
        tertiary: Color(0xFFCB9524),
        onTertiary: Color(0xFFFFFFFF),
        tertiaryContainer: Color(0xFF493100),
        onTertiaryContainer: Color(0xFFCB9524),
        error: Color(0xFFBA1A1A),
        onError: Color(0xFFFFFFFF),
        errorContainer: Color(0xFFFFDAD6),
        onErrorContainer: Color(0xFF93000A),
        surface: Color(0xFFF9F9FF),
        onSurface: Color(0xFF111C2C),
        surfaceContainerHighest: Color(0xFFD8E3FA),
        onSurfaceVariant: Color(0xFF43474E),
        outline: Color(0xFF74777F),
        outlineVariant: Color(0xFFC4C6CF),
        inverseSurface: Color(0xFF263142),
        inversePrimary: Color(0xFFADC7F7),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF002045),
        foregroundColor: Color(0xFFFFFFFF),
        elevation: 0,
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(color: Color(0xFF002045), fontWeight: AppSpacing.weightStrong),
        bodyMedium: TextStyle(color: Color(0xFF111C2C)),
        bodySmall: TextStyle(color: Color(0xFF43474E)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minVerticalPadding: 8,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: Color(0xFF002045),
        unselectedLabelColor: Color(0xFF43474E),
        indicatorColor: Color(0xFF002045),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style:         ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF002045),
          foregroundColor: const Color(0xFFFFFFFF),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFC4C6CF)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFC4C6CF)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFFF9F9FF),
        selectedItemColor: Color(0xFF002045),
        unselectedItemColor: Color(0xFF74777F),
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFC4C6CF)),
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
      primaryColor: const Color(0xFF1A365D),
      scaffoldBackgroundColor: const Color(0xFF0F172A),
      colorScheme: const ColorScheme(
        brightness: Brightness.dark,
        primary: Color(0xFFADC7F7),
        onPrimary: Color(0xFF102F58),
        primaryContainer: Color(0xFF2D476F),
        onPrimaryContainer: Color(0xFFD6E3FF),
        secondary: Color(0xFF89D3D4),
        onSecondary: Color(0xFF003737),
        secondaryContainer: Color(0xFF004F50),
        onSecondaryContainer: Color(0xFFA5EFF0),
        tertiary: Color(0xFFF8BC4B),
        onTertiary: Color(0xFF3E2B00),
        tertiaryContainer: Color(0xFF5F4100),
        onTertiaryContainer: Color(0xFFFFDEAA),
        error: Color(0xFFFFB4AB),
        onError: Color(0xFF690005),
        errorContainer: Color(0xFF93000A),
        onErrorContainer: Color(0xFFFFDAD6),
        surface: Color(0xFF0F172A),
        onSurface: Color(0xFFEBF1FF),
        surfaceContainerHighest: Color(0xFF1E293B),
        onSurfaceVariant: Color(0xFFC4C6CF),
        outline: Color(0xFF8E9099),
        outlineVariant: Color(0xFF43474E),
        inverseSurface: Color(0xFFEBF1FF),
        inversePrimary: Color(0xFF002045),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF020617),
        foregroundColor: Color(0xFFEBF1FF),
        elevation: 0,
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(color: Color(0xFFEBF1FF), fontWeight: AppSpacing.weightStrong),
        bodyMedium: TextStyle(color: Color(0xFFEBF1FF)),
        bodySmall: TextStyle(color: Color(0xFFC4C6CF)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minVerticalPadding: 8,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: Color(0xFFEBF1FF),
        unselectedLabelColor: Color(0xFFC4C6CF),
        indicatorColor: Color(0xFFADC7F7),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFADC7F7),
          foregroundColor: const Color(0xFF102F58),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF43474E)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF43474E)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF0F172A),
        selectedItemColor: Color(0xFFADC7F7),
        unselectedItemColor: Color(0xFF8E9099),
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF43474E)),
        ),
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }
}
