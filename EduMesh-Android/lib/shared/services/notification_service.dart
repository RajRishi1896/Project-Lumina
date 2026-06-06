import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// A singleton service for managing local notification display and permissions.
///
/// Handles initialization of the [FlutterLocalNotificationsPlugin], creation of the
/// `download_channel` on Android, and toggling notification preferences via
/// [SharedPreferences]. The [showDownloadComplete] method is called by [DownloadQueue]
/// when a file finishes downloading.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const String _prefKey = 'notifications_enabled';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _nextId = 1000;

  /// Initializes the notification plugin and creates the download channel.
  ///
  /// Must be called at least once before showing notifications. Calling
  /// multiple times is safe — subsequent calls are no-ops.
  Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(android: android, iOS: ios);
    await _plugin.initialize(settings);
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'download_channel',
          'Downloads',
          description: 'Download completion notifications',
          importance: Importance.defaultImportance,
        ),
      );
    }
    _initialized = true;
  }

  /// Whether notifications are enabled in user preferences.
  Future<bool> get isEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? true;
  }

  /// Enables or disables notifications and clears any pending notifications
  /// when disabled.
  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
    if (!value) {
      await _plugin.cancelAll();
    }
  }

  /// Whether the user has granted notification permission.
  ///
  /// On Android 13+ this triggers the system permission dialog if not yet decided.
  /// On Android <13 the permission is auto-granted from the manifest and the
  /// plugin returns `null`, which this method treats as granted (`!= false`).
  /// Returns `false` on non-Android platforms where the plugin is unavailable.
  Future<bool> requestPermission() async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return false;
    final granted = await androidPlugin.requestNotificationsPermission();
    return granted != false;
  }

  /// Shows a local notification confirming a download finished.
  ///
  /// Checks [isEnabled] and initializes the plugin if needed. Calls
  /// [requestPermission] immediately before showing — on Android 13+ this
  /// surfaces the permission prompt at a natural UX moment (right after the
  /// user triggered a download).
  Future<void> showDownloadComplete(String title) async {
    if (!await isEnabled) return;
    if (!_initialized) await init();
    await requestPermission();
    try {
      await _plugin.show(
        _nextId++,
        'Download Complete',
        '"$title" has been downloaded and saved to offline storage.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'download_channel',
            'Downloads',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint("NotificationService: show failed: $e");
    }
  }
}
