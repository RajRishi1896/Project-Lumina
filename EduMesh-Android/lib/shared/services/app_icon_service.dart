import 'package:flutter/services.dart';

/// Manages the Android app icon via a platform channel.
///
/// Wraps [MethodChannel] to switch between light and dark adaptive launcher icons.
class AppIconService {
  static const _channel = MethodChannel('com.edumesh.android/app_icon');

  /// Switch the app launcher icon to light or dark.
  static Future<void> setAppIcon(bool useDark) async {
    try {
      await _channel.invokeMethod('setAppIcon', {'useDark': useDark});
    } catch (_) { } }

  /// Whether the currently active app icon is the dark variant.
  static Future<bool> isDarkIcon() async {
    try {
      final result = await _channel.invokeMethod<bool>('isDarkIcon');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}
