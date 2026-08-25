import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart' show DioException;

// Ensure these imports match your project structure exactly
import 'package:edumesh_android/core/theme/lumina_lite_theme.dart';
import 'package:edumesh_android/core/theme/theme_provider.dart';
import 'package:edumesh_android/shared/services/app_icon_service.dart' show setAppIcon;
import 'package:edumesh_android/features/auth/presentation/welcome_page.dart';
import 'package:edumesh_android/features/auth/presentation/profile_picker_page.dart';
import 'package:edumesh_android/features/auth/data/auth_service.dart';
import 'package:edumesh_android/widgets/connection_gate.dart';
import 'package:edumesh_android/pages/app_shell.dart';
import 'package:edumesh_android/core/network/api_client.dart';
import 'package:edumesh_android/shared/services/notification_service.dart';
import 'package:edumesh_android/shared/services/connectivity_service.dart';
import 'package:edumesh_android/core/services/activity_tracker.dart';
import 'package:edumesh_android/core/providers/locale_provider.dart';
import 'package:edumesh_android/core/providers/animation_prefs.dart';
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
  // TEMP DIAGNOSTIC: capture the silent NoSuchMethodError (remove after).
  FlutterError.onError = (details) {
    debugPrint('LUMINA_ERR: ${details.exception}');
    debugPrint('LUMINA_STACK: ${details.stack}');
  };
  unawaited(AnimationPrefs().load());
  _trace('T0 start ${DateTime.now().microsecondsSinceEpoch}');

  // All platform-thread-heavy plugin init is deferred to after the first
  // frame so it can't stall the secure-storage read on the critical path
  // (first plugin call queues behind flutter_local_notifications setup).
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await NotificationService().init();
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await setAppIcon(prefs.getBool('dark_app_icon') ?? false);
    } catch (_) {}
  });

  final authService = AuthService();
  String? userId;
  try {
    userId = await authService.getUniqueUserId();
  } catch (_) {
    // ponytail: secure-storage read throws on keystore corruption (e.g. lock
    // screen removed): treat as logged out instead of crashing before runApp.
  }
  _trace('T2 userId=$userId ${DateTime.now().microsecondsSinceEpoch}');
  bool isLoggedIn = userId != null;

  // Assigned BEFORE the profile probe: a 401 during the probe hits the
  // force-logout path, and a late assignment would leave it null (or crash
  // on navigatorKey.currentState! before the first frame mounts the navigator).
  ApiClient.onForceLogout = () {
    final navigator = navigatorKey.currentState;
    if (navigator != null) unawaited(routeAfterLogout(navigator));
  };

  // Validate that the stored user still exists on the server.
  // Deferred to first frame so an unreachable hub can't hold cold start hostage.
  // A 401 during any later request hits the force-logout path anyway.
  if (isLoggedIn) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ApiClient.get('/student/profile');
      } on DioException catch (e) {
        // Dio throws on non-2xx: a 401/404 here means the stored account no
        // longer exists on the hub. The interceptor also force-logs-out on
        // 401; this keeps the probe's own path correct if it ever fires first.
        final code = e.response?.statusCode;
        if (code == 401 || code == 404) {
          final navigator = navigatorKey.currentState;
          if (navigator != null) unawaited(routeAfterLogout(navigator));
        }
      } catch (_) {}
    });
  }

  try { ConnectivityService().start(); } catch (_) {}
  try { ActivityTracker().startAutoSync(); } catch (_) {}

  unawaited(_initBackgroundService().onError((_, __) {}));
  _trace('T4 bgservice ${DateTime.now().microsecondsSinceEpoch}');
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
  final l10n = await _backgroundL10n();
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _onBackgroundStart,
      autoStart: false,
      autoStartOnBoot: false,
      isForegroundMode: true,
      foregroundServiceTypes: [AndroidForegroundType.dataSync],
      notificationChannelId: 'download_channel',
      initialNotificationTitle: l10n.downloadActiveNotificationTitle,
      initialNotificationContent: l10n.downloadActiveNotificationContent,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
    ),
  );
}

/// Cold-start trace marks, kept for performance measurement runs.
///
/// Gated by [kDebugMode] so release builds don't spam logcat.
void _trace(String message) {
  if (kDebugMode) debugPrint(message);
}

/// Localizations for the background-service notification strings, resolved
/// from the persisted app locale without a [BuildContext].
Future<AppLocalizations> _backgroundL10n() async {
  String code = 'en';
  try {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('app_locale');
    if (saved != null && appSupportedLocales.any((l) => l.languageCode == saved)) {
      code = saved;
    }
  } catch (_) {}
  return lookupAppLocalizations(Locale(code));
}

@pragma('vm:entry-point')
Future<void> _onBackgroundStart(ServiceInstance service) async {
  // This isolate is spawned by flutter_background_service without plugin
  // registration; plugins (SharedPreferences) fail without this call.
  DartPluginRegistrant.ensureInitialized();
  service.on('stop').listen((_) {
    service.stopSelf();
  });

  // Latest download percent reported by DownloadQueue in the main isolate.
  // The foreground-service notification is the single progress indicator.
  // Registered BEFORE the awaited l10n setup below: progress invokes arriving
  // during that async gap would otherwise be dropped.
  int latestPercent = -1;
  service.on('progress').listen((message) {
    final pct = (message?['percent'] as num?)?.toInt();
    if (pct != null && pct >= 0 && pct <= 100) latestPercent = pct;
  });

  final l10n = await _backgroundL10n();

  Timer.periodic(const Duration(seconds: 30), (_) async {
    if (service is AndroidServiceInstance) {
      final content = latestPercent >= 0
          ? l10n.notifDownloading('$latestPercent${l10n.suffixPercent}')
          : l10n.downloadInProgressNotificationContent;
      await service.setForegroundNotificationInfo(
        title: l10n.downloadInProgressNotificationTitle,
        content: content,
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
  /// Guards the one-time provider hydration so [build] stays side-effect
  /// free on every rebuild after the first.
  static bool _providersLoaded = false;

  final bool isLoggedIn;

  const LuminaApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_providersLoaded) {
      _providersLoaded = true;
      ref.read(localeProvider.notifier).load();
      ref.read(themeModeProvider.notifier).load();
    }
    final themeMode = ref.watch(themeModeProvider);

    // ponytail: the design size IS the viewport, clamped. ScreenUtil scale
    // factors become width/designW and height/designH, so clamping the design
    // size to the phone baseline caps every scale at ~1.5x on tablets and
    // keeps 1.0x on phones, in any orientation, without device checks.
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final logicalSize = view.physicalSize / view.devicePixelRatio;
    final designSize = Size(
      logicalSize.width.clamp(360.0, 1280.0),
      logicalSize.height.clamp(640.0, 1280.0),
    );
    return ScreenUtilInit(
      designSize: designSize,
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
            NotificationService().setStrings(
              channelName: l10n.downloadChannelName,
              channelDescription: l10n.downloadChannelDescription,
              completeTitle: l10n.downloadCompleteNotificationTitle,
              completeBody: l10n.downloadCompleteNotificationBody('{title}'),
              failedTitle: l10n.downloadFailedNotificationTitle,
              failedBody: l10n.downloadFailedNotificationBody('{title}'),
              removedTitle: l10n.removedFromServerNotificationTitle,
              removedBody: l10n.removedFromServerNotificationBody('{title}'),
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
