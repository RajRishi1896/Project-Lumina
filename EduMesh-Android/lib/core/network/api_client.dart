import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/auth/data/auth_service.dart';
import '../demo/demo_data.dart';

class ApiClient {
  // Now using the official Mesh Domain we set up on Debian
  static const String _defaultDomain = 'http://lumina.hub:8000';
  static String _baseUrl = _defaultDomain;
  static bool _initialized = false;

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(seconds: 10), // Increased for mesh stability
    receiveTimeout: const Duration(seconds: 15),
    sendTimeout: const Duration(seconds: 10),
    responseType: ResponseType.json,
  ))
    ..interceptors.add(LogInterceptor(requestBody: false, responseBody: false));

  static void setAuth(String token) {
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  static void clearAuth() {
    _dio.options.headers.remove('Authorization');
  }

  // Ensure the base URL is resolved before any request
  static Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final fallbackIp = prefs.getString('server_fallback_ip');
      if (fallbackIp != null && fallbackIp.isNotEmpty) {
        _baseUrl = 'http://$fallbackIp:8000';
        debugPrint('ApiClient: Using fallback IP $fallbackIp');
      } else {
        // Try DNS/mDNS resolution
        try {
          final result = await InternetAddress.lookup('lumina.hub');
          if (result.isNotEmpty) {
            _baseUrl = _defaultDomain;
            debugPrint('ApiClient: DNS lookup succeeded, using default domain');
          }
        } catch (_) {
          // DNS failed, keep default (which may be unreachable)
          debugPrint('ApiClient: DNS lookup failed, keeping default domain');
        }
      }
      _dio.options.baseUrl = _baseUrl;
    } catch (e) {
      debugPrint('ApiClient initialization error: $e');
    }
    _initialized = true;
  }


  static Future<Response<T>> get<T>(String path, {Map<String, dynamic>? queryParameters}) async {
    if (AuthService.isDemoMode) {
      final demoResp = DemoData.response<T>(path, queryParameters);
      if (demoResp != null) return demoResp;
    }
    await _ensureInitialized();
    return _dio.get<T>(path, queryParameters: queryParameters);
  }

  static Future<Response<T>> post<T>(String path, {dynamic data, Map<String, dynamic>? queryParameters}) async {
    if (AuthService.isDemoMode) {
      final demoResp = DemoData.response<T>(path, queryParameters);
      if (demoResp != null) return demoResp;
    }
    await _ensureInitialized();
    return _dio.post<T>(path, data: data, queryParameters: queryParameters);
  }

  static Future<Response<T>> delete<T>(String path, {dynamic data, Map<String, dynamic>? queryParameters}) async {
    if (AuthService.isDemoMode) {
      final demoResp = DemoData.response<T>(path, queryParameters);
      if (demoResp != null) return demoResp;
    }
    await _ensureInitialized();
    return _dio.delete<T>(path, data: data, queryParameters: queryParameters);
  }
  
  static Dio get dio {
    // Intentionally not calling _ensureInitialized here — caller
    // should call ensureInitialized() if they need base URL resolution.
    return _dio;
  }

  static Future<void> ensureInitialized() => _ensureInitialized();

  static void setBaseUrl(String url) {
    _dio.options.baseUrl = url;
  }
}
