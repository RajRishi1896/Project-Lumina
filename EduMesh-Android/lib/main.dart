import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Ensure these imports match your project structure exactly
import 'package:edumesh_android/core/theme/lumina_lite_theme.dart';
import 'package:edumesh_android/core/theme/theme_provider.dart';
import 'package:edumesh_android/shared/services/app_icon_service.dart' show setAppIcon;
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
import 'package:edumesh_android/shared/services/download_service.dart';
import 'package:edumesh_android/shared/services/share_server.dart';

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
  unawaited(NotificationService().init().catchError((_) {}));

  final prefs = await SharedPreferences.getInstance();
  final useDarkIcon = prefs.getBool('dark_app_icon') ?? false;
  unawaited(setAppIcon(useDarkIcon).catchError((_) {}));

  final authService = AuthService();
  String? userId;
  try {
    userId = await authService.getUniqueUserId();
  } catch (_) {
    // ponytail: secure-storage read throws on keystore corruption (e.g. lock
    // screen removed) -- treat as logged out instead of crashing before runApp.
  }
  bool isLoggedIn = userId != null;

  // Validate that the stored user still exists on the server.
  // Prevents N concurrent 401 handlers from crashing the app when a
  // logged-in student was deleted from the server. Timeboxed so an
  // unreachable hub can't hold cold start hostage.
  if (isLoggedIn) {
    try {
      await ApiClient.get('/student/profile').timeout(const Duration(seconds: 5));
    } catch (e) {
      if (e is DioException &&
          (e.response?.statusCode == 401 || e.response?.statusCode == 404)) {
        isLoggedIn = false;
      }
    }
  }

  ApiClient.onForceLogout = () {
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomePage()),
      (route) => false,
    );
  };

  try { ConnectivityService().start(); } catch (_) {}
  try { ActivityTracker().startAutoSync(); } catch (_) {}

  try { await _initBackgroundService(); } catch (_) {}
  unawaited(DownloadService.cleanStaleParts(const Duration(days: 7)));

  runApp(
    ProviderScope(
      child: LuminaApp(isLoggedIn: isLoggedIn),
    ),
  );

  // Start peer-to-peer file sharing after the first frame, only when the
  // student left the share setting ON. Safe: start() binds nothing if OFF.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await ShareServer().start();
    } catch (_) {}
  });
}

Future<void> _initBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _onBackgroundStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'download_channel',
      initialNotificationTitle: 'EduMesh',
      initialNotificationContent: 'Downloads active',
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
    ),
  );
}

@pragma('vm:entry-point')
Future<void> _onBackgroundStart(ServiceInstance service) async {
  service.on('stop').listen((_) {
    service.stopSelf();
  });

  Timer.periodic(const Duration(seconds: 30), (_) async {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'EduMesh Downloads',
        content: 'Downloads in progress...',
      );
    }
  });
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
    ref.read(localeProvider.notifier).load();
    ref.read(themeModeProvider.notifier).load();
    final themeMode = ref.watch(themeModeProvider);

    return ScreenUtilInit(
      designSize: const Size(360, 800),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          onGenerateTitle: (context) => AppLocalizations.of(context)!.materialAppTitle,
          theme: LuminaLiteTheme.lightTheme,
          darkTheme: LuminaLiteTheme.darkTheme,
          themeMode: themeMode,
          debugShowCheckedModeBanner: false,
          locale: ref.watch(localeProvider),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) {
            final l10n = AppLocalizations.of(context)!;
            NotificationService().setLocalizedStrings(
              channelName: l10n.downloadChannelName,
              channelDescription: l10n.downloadChannelDescription,
              downloadCompleteTitle: l10n.downloadCompleteNotificationTitle,
              downloadCompleteBody: l10n.downloadCompleteNotificationBody('{title}'),
              downloadFailedTitle: l10n.downloadFailedNotificationTitle,
              downloadFailedBody: l10n.downloadFailedNotificationBody('{title}'),
              downloadInProgressTitle: l10n.notifDownloadsActive,
              downloadInProgressBody: l10n.notifDownloading('{title}'),
            );
            NotificationService().setRemovedStrings(
              title: l10n.removedFromServerNotificationTitle,
              body: l10n.removedFromServerNotificationBody('{title}'),
            );
            return child!;
          },
          home: isLoggedIn
            ? const ConnectionGate(child: AppShell())
            : const WelcomePage(),
        );
      },
    );
  }
}
