import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Ensure these imports match your project structure exactly
import 'package:edumesh_android/core/theme/lumina_lite_theme.dart';
import 'package:edumesh_android/core/theme/theme_provider.dart'; 
import 'package:edumesh_android/features/auth/presentation/welcome_page.dart';
import 'package:edumesh_android/features/auth/data/auth_service.dart';
import 'package:edumesh_android/widgets/connection_gate.dart';
import 'package:edumesh_android/pages/app_shell.dart';
import 'package:edumesh_android/core/network/api_client.dart';
import 'package:edumesh_android/shared/services/notification_service.dart';
import 'package:edumesh_android/shared/services/connectivity_service.dart';
import 'package:edumesh_android/core/services/activity_tracker.dart';
import 'package:edumesh_android/core/providers/locale_provider.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';

/// The global [NavigatorState] key used for out-of-widget navigation.
///
/// Referenced by [ApiClient.onForceLogout] to navigate to the [WelcomePage]
/// when the session expires.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// The application entry point.
///
/// Initialises [NotificationService], reads the persisted theme preference,
/// resolves the user's authentication status, starts [ConnectivityService]
/// and [ActivityTracker], and finally runs the [LuminaApp] widget inside a
/// [ProviderScope].
void main() async { 
  WidgetsFlutterBinding.ensureInitialized();
  NotificationService().init();

  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('dark_mode') ?? false;
  final initialThemeMode = isDark ? ThemeMode.dark : ThemeMode.light;

  final authService = AuthService();
  final userId = await authService.getUniqueUserId();
  final bool isLoggedIn = userId != null;

  ApiClient.onForceLogout = () {
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomePage()),
      (route) => false,
    );
  };

  ConnectivityService().start();
  ActivityTracker().startAutoSync();

  runApp(
    ProviderScope(
      overrides: [
        initialThemeProvider.overrideWithValue(initialThemeMode),
      ],
      child: LuminaApp(isLoggedIn: isLoggedIn),
    ),
  );
}

/// The root MaterialApp widget for Edu-Mesh Scholar.
///
/// Configures light and dark themes via [LuminaLiteTheme], sets up
/// [ScreenUtilInit] for responsive sizing, and displays either the
/// main [AppShell] or the [WelcomePage] based on [isLoggedIn].
class LuminaApp extends ConsumerWidget {
  /// Whether the user has an active session.
  final bool isLoggedIn;

  const LuminaApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return ScreenUtilInit(
      designSize: const Size(360, 800),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'Edu-Mesh Scholar',
          theme: LuminaLiteTheme.lightTheme,
          darkTheme: LuminaLiteTheme.darkTheme,
          themeMode: themeMode, 
          debugShowCheckedModeBanner: false,
          locale: ref.watch(localeProvider),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: isLoggedIn 
            ? const ConnectionGate(child: AppShell()) 
            : const WelcomePage(),
        );
      },
    );
  }
}
