import 'package:flutter/services.dart';

const _channel = MethodChannel('com.edumesh.android/app_icon');

/// Switches the launcher icon between light and dark variants.
Future<void> setAppIcon(bool useDark) async {
  try {
    await _channel.invokeMethod('setAppIcon', {'useDark': useDark});
  } catch (_) { }
}

