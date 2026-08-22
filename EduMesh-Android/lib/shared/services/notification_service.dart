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

  // Localized strings for notifications and channel metadata: set via
  // [setStrings] when a BuildContext is available. Defaults are English
  // fallbacks (same values as the ARB keys in app_en.arb).
  String _channelName = 'Downloads';
  String _channelDescription = 'Download completion notifications';
  String _completeNotificationTitle = 'Download Complete';
  String _failedNotificationTitle = 'Download Failed';
  String _completeNotificationBody = '"{title}" has been downloaded and saved to offline storage.';
  String _failedNotificationBody = '"{title}" could not be downloaded. Check the server connection and try again.';
  String _removedNotificationTitle = 'Removed from server';
  String _removedNotificationBody = '"{title}" was removed from the server. You can keep using it offline, but it can no longer be redownloaded.';

  /// Initializes the notification plugin and creates the download channel.
  ///
  /// Must be called at least once before showing notifications. Calling
  /// multiple times is safe: subsequent calls are no-ops.
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
    await _createChannel();
    _initialized = true;
  }

  Future<void> _createChannel() async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        AndroidNotificationChannel(
          'download_channel',
          _channelName,
          description: _channelDescription,
        ),
      );
    }
  }

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

  /// Shows a local notification confirming a download finished.
  ///
  /// Checks [isEnabled] and initializes the plugin if needed. Requests
  /// permission immediately before showing: on Android 13+ this surfaces the
  /// permission prompt at a natural UX moment (right after the user
  /// triggered a download).
  Future<void> showDownloadComplete(String title) {
    return _show(
      id: _nextId++,
      title: _completeNotificationTitle,
      body: _completeNotificationBody.replaceAll('{title}', title),
    );
  }

  /// Shows a local notification that a downloaded resource was removed from
  /// the server catalog. The local file remains usable offline.
  ///
  /// Uses the same channel and permission flow as [showDownloadComplete].
  Future<void> showRemovedFromServer(String title) {
    return _show(
      id: _nextId++,
      title: _removedNotificationTitle,
      body: _removedNotificationBody.replaceAll('{title}', title),
    );
  }

  /// Sets all localized notification strings.
  ///
  /// Call this with [AppLocalizations] values when a [BuildContext] is
  /// available (e.g. in the MaterialApp builder). The English values assigned
  /// above are fallbacks for anything shown before the first frame.
  void setStrings({
    required String channelName,
    required String channelDescription,
    required String completeTitle,
    required String completeBody,
    required String failedTitle,
    required String failedBody,
    required String removedTitle,
    required String removedBody,
  }) {
    _channelName = channelName;
    _channelDescription = channelDescription;
    _completeNotificationTitle = completeTitle;
    _completeNotificationBody = completeBody;
    _failedNotificationTitle = failedTitle;
    _failedNotificationBody = failedBody;
    _removedNotificationTitle = removedTitle;
    _removedNotificationBody = removedBody;
  }

  /// Shows a local notification when a download fails after all retries.
  ///
  /// Uses the same channel and permission flow as [showDownloadComplete].
  Future<void> showDownloadFailed(String title) {
    return _show(
      id: _nextId++,
      title: _failedNotificationTitle,
      body: _failedNotificationBody.replaceAll('{title}', title),
    );
  }

  /// Requests permission, initializes the plugin, and shows a notification.
  ///
  /// Returns early when the user denied the notification permission. A denial
  /// is not cached: the next notification asks again, so a dismissed system
  /// dialog doesn't silence notifications for the rest of the app run.
  /// On Android <13 the plugin returns `null`, treated as granted.
  Future<void> _show({required int id, required String title, required String body, AndroidNotificationDetails? androidDetails}) async {
    try {
      if (!await isEnabled) return;
      if (!_initialized) await init();
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null && await androidPlugin.requestNotificationsPermission() == false) return;
    } catch (_) {
      return;
    }
    try {
      await _plugin.show(
        id,
        title,
        body,
        NotificationDetails(
          android: androidDetails ??
              AndroidNotificationDetails(
                'download_channel',
                _channelName,
              ),
          iOS: const DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('NotificationService: show failed: $e');
    }
  }
}
