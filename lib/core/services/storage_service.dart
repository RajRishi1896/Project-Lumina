import 'package:flutter/services.dart';

class StorageService {
  static const _channel = MethodChannel('com.edumesh.android/storage');

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
