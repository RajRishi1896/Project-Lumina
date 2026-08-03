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

  // Configurable strings for localization -- set via [setLocalizedStrings]
  // when a BuildContext is available. Defaults are English fallbacks.
  String _channelName = 'Downloads';
  String _channelDescription = 'Download completion notifications';
  String _completeNotificationTitle = 'Download Complete';
  String _failedNotificationTitle = 'Download Failed';
  String _inProgressNotificationTitle = 'Downloading...';
  String _inProgressNotificationBodyTemplate = '{title} ({percent}%)';
  // English fallbacks (same values as the ARB keys in app_en.arb). Replaced
  // with locals via [setLocalizedStrings] once a BuildContext is available.
  String _completeNotificationBody = '"{title}" has been downloaded and saved to offline storage.';
  String _failedNotificationBody = '"{title}" could not be downloaded. Check the server connection and try again.';

  /// Initializes the notification plugin and creates the download channel.
  ///
  /// Must be called at least once before showing notifications. Calling
  /// multiple times is safe -- subsequent calls are no-ops.
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

  bool _permissionRequested = false;
  bool _permissionGranted = false;

  /// Requests notification permission at most once per app run so the Android
  /// 13+ system dialog is not re-shown for every notification.
  Future<bool> _ensurePermission() async {
    if (_permissionRequested) return _permissionGranted;
    _permissionRequested = true;
    _permissionGranted = await requestPermission();
    return _permissionGranted;
  }

  /// Shows a local notification confirming a download finished.
  ///
  /// Checks [isEnabled] and initializes the plugin if needed. Calls
  /// [requestPermission] immediately before showing -- on Android 13+ this
  /// surfaces the permission prompt at a natural UX moment (right after the
  /// user triggered a download).
  Future<void> showDownloadComplete(String title, {String? notificationTitle, String? notificationBody}) async {
    try {
      if (!await isEnabled) return;
      if (!_initialized) await init();
      await _ensurePermission();
    } catch (_) {
      // ponytail: permission/init failures are non-fatal; skip notification
      return;
    }
    try {
      await _plugin.show(
        _nextId++,
        notificationTitle ?? _completeNotificationTitle,
        (notificationBody ?? _completeNotificationBody).replaceAll('{title}', title),
        NotificationDetails(
          android: AndroidNotificationDetails(
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

  /// Sets localized strings for notifications.
  ///
  /// Call this with [AppLocalizations] values when a [BuildContext] is
  /// available (e.g. in [LuminaApp.build] or after locale change).
  void setLocalizedStrings({
    String? channelName,
    String? channelDescription,
    String? downloadCompleteTitle,
    String? downloadCompleteBody,
    String? downloadFailedTitle,
    String? downloadFailedBody,
    String? downloadInProgressTitle,
    String? downloadInProgressBody,
  }) {
    if (channelName != null) _channelName = channelName;
    if (channelDescription != null) _channelDescription = channelDescription;
    if (downloadCompleteTitle != null) _completeNotificationTitle = downloadCompleteTitle;
    if (downloadCompleteBody != null) _completeNotificationBody = downloadCompleteBody;
    if (downloadFailedTitle != null) _failedNotificationTitle = downloadFailedTitle;
    if (downloadFailedBody != null) _failedNotificationBody = downloadFailedBody;
    if (downloadInProgressTitle != null) _inProgressNotificationTitle = downloadInProgressTitle;
    if (downloadInProgressBody != null) _inProgressNotificationBodyTemplate = downloadInProgressBody;
  }

  /// Shows a local notification when a download fails after all retries.
  ///
  /// Uses the same channel and permission flow as [showDownloadComplete].
  Future<void> showDownloadFailed(String title, {String? notificationTitle, String? notificationBody}) async {
    try {
      if (!await isEnabled) return;
      if (!_initialized) await init();
      await _ensurePermission();
    } catch (_) {
      return;
    }
    try {
      await _plugin.show(
        _nextId++,
        notificationTitle ?? _failedNotificationTitle,
        (notificationBody ?? _failedNotificationBody).replaceAll('{title}', title),
        NotificationDetails(
          android: AndroidNotificationDetails(
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

  /// Shows or updates a progress notification for an active download.
  Future<void> showDownloadProgress(String title, int percent, {required int id, String? notificationTitle, String? notificationBody}) async {
    try {
      if (!await isEnabled) return;
      if (!_initialized) await init();
      await _ensurePermission();
    } catch (_) {
      return;
    }
    try {
      final resolvedBody = (notificationBody ?? _inProgressNotificationBodyTemplate)
          .replaceAll('{title}', title)
          .replaceAll('{percent}', '$percent');
      await _plugin.show(
        id,
        notificationTitle ?? _inProgressNotificationTitle,
        resolvedBody,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'download_channel',
            _channelName,
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            showProgress: true,
            maxProgress: 100,
            progress: percent,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('NotificationService: progress show failed: $e');
    }
  }

  /// Cancels a progress notification by [id].
  Future<void> cancelProgressNotification(int id) async {
    try {
      await _plugin.cancel(id);
    } catch (e) {
      debugPrint('NotificationService: cancel failed: $e');
    }
  }
}
