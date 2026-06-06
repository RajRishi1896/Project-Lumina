import 'package:flutter/services.dart';

/// A service that queries the native platform for device storage information.
class StorageService {
  static const _channel = MethodChannel('com.edumesh.android/storage');

  /// A map of `totalBytes` and `availableBytes` on the device's internal storage.
  /// Falls back to reasonable defaults (128 GB total, 64 GB available) if the
  /// native call fails.
  Future<Map<String, int>> getStorageInfo() async {
    try {
      final Map<dynamic, dynamic>? info = await _channel.invokeMethod('getStorageInfo');
      if (info != null) {
        return {
          'totalBytes': info['totalBytes'] as int,
          'availableBytes': info['availableBytes'] as int,
        };
      }
    } catch (e) {
      // Fallback to reasonable defaults if native call fails
    }
    return {
      'totalBytes': 128 * 1024 * 1024 * 1024,
      'availableBytes': 64 * 1024 * 1024 * 1024,
    };
  }
}
