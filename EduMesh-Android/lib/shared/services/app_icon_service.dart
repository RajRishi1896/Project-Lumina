import 'package:flutter/services.dart';

class AppIconService {
  static const _channel = MethodChannel('com.edumesh.android/app_icon');

  static Future<void> setAppIcon(bool useDark) async {
    try {
      await _channel.invokeMethod('setAppIcon', {'useDark': useDark});
    } catch (_) {}
  }

  static Future<bool> isDarkIcon() async {
    try {
      final result = await _channel.invokeMethod<bool>('isDarkIcon');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}
