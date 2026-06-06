import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/auth/data/auth_service.dart';

/// A singleton HTTP client wrapper around [Dio] that handles server discovery,
/// token-based authentication, and automatic retry on 401/403 responses.
class ApiClient {
  // Now using the official Mesh Domain we set up on Debian
  static const String _defaultDomain = 'http://lumina.hub:8000';
  static String _baseUrl = _defaultDomain;
  static bool _initialized = false;
  static int _initAttempts = 0;
  static bool _isRefreshing = false;

  /// Callback invoked when a token refresh fails and the user must be logged out.
  static void Function()? onForceLogout;

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(seconds: 10), // Increased for mesh stability
    receiveTimeout: const Duration(seconds: 15),
    sendTimeout: const Duration(seconds: 10),
    responseType: ResponseType.json,
  ))
    ..interceptors.add(LogInterceptor(requestBody: false, responseBody: false))
    ..interceptors.add(InterceptorsWrapper(
      onError: (error, handler) async {
        if ((error.response?.statusCode == 401 || error.response?.statusCode == 403) && !_isRefreshing) {
          _isRefreshing = true;
          try {
            if (await AuthService().refreshSession()) {
              final newToken = await AuthService().getSessionToken();
              error.requestOptions.headers['Authorization'] = 'Bearer $newToken';
              try {
                final retryResponse = await _dio.fetch(error.requestOptions);
                handler.resolve(retryResponse);
                return;
              } catch (_) {
                handler.next(error);
                return;
              }
            }
            await AuthService().logout();
            onForceLogout?.call();
          } finally {
            _isRefreshing = false;
          }
        }
        handler.next(error);
      },
    ));

  static bool _keepAliveConfigured = false;

  static void _configureKeepAlive() {
    if (_keepAliveConfigured) return;
    (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.idleTimeout = const Duration(seconds: 30);
      client.connectionTimeout = const Duration(seconds: 10);
      return client;
    };
    _keepAliveConfigured = true;
  }

  /// Sets the [token] on all outgoing requests as a Bearer authorization header.
  static void setAuth(String token) {
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  /// Removes the Bearer authorization header from all outgoing requests.
  static void clearAuth() {
    _dio.options.headers.remove('Authorization');
  }

  // Ensure the base URL is resolved before any request
  static Future<void> _initLock = Future.value();
  static Future<void> _ensureInitialized() async {
    _configureKeepAlive();
    if (_initialized) return;
    if (_initAttempts >= 3) {
      _dio.options.baseUrl = _baseUrl;
      return;
    }
    // Only allow one caller to init at a time
    if (_initAttempts > 0 && !_initialized) {
      await _initLock;
      if (_initialized) return;
    }
    _initAttempts++;
    _initLock = _doInitialize();
    await _initLock;
  }

  static Future<void> _doInitialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final fallbackIp = prefs.getString('server_fallback_ip');
      if (fallbackIp != null && fallbackIp.isNotEmpty) {
        _baseUrl = 'http://$fallbackIp:8000';
        debugPrint('ApiClient: Using fallback IP $fallbackIp');
      } else {
        try {
          final result = await InternetAddress.lookup('lumina.hub')
              .timeout(const Duration(seconds: 3));
          if (result.isNotEmpty) {
            _baseUrl = _defaultDomain;
            debugPrint('ApiClient: DNS lookup succeeded, using default domain');
          }
        } catch (_) {
          _baseUrl = 'http://10.42.0.1:8000';
          debugPrint('ApiClient: DNS failed, falling back to 10.42.0.1');
        }
      }
      _dio.options.baseUrl = _baseUrl;
      _initialized = true;
      _initAttempts = 0;
    } catch (e) {
      debugPrint('ApiClient initialization error: $e');
      // Mark initialized anyway so we don't keep retrying DNS
      _dio.options.baseUrl = _baseUrl;
      _initialized = true;
      _initAttempts = 0;
    }
  }


  /// Sends a GET request to the given [path] with optional [queryParameters].
  /// Resolves the server base URL first via [_ensureInitialized].
  static Future<Response<T>> get<T>(String path, {Map<String, dynamic>? queryParameters, CancelToken? cancelToken}) async {
    await _ensureInitialized();
    return _dio.get<T>(path, queryParameters: queryParameters, cancelToken: cancelToken);
  }

  /// Sends a POST request to the given [path] with optional [data] and [queryParameters].
  /// Resolves the server base URL first via [_ensureInitialized].
  static Future<Response<T>> post<T>(String path, {dynamic data, Map<String, dynamic>? queryParameters}) async {
    await _ensureInitialized();
    return _dio.post<T>(path, data: data, queryParameters: queryParameters);
  }

  /// Sends a DELETE request to the given [path] with optional [data] and [queryParameters].
  /// Resolves the server base URL first via [_ensureInitialized].
  static Future<Response<T>> delete<T>(String path, {dynamic data, Map<String, dynamic>? queryParameters}) async {
    await _ensureInitialized();
    return _dio.delete<T>(path, data: data, queryParameters: queryParameters);
  }
  
  /// Executes the given [request] function with automatic retry on failure.
  /// Retries up to [maxRetries] times with an [initialDelay] that doubles each attempt.
  /// Throws if all retries are exhausted.
  static Future<Response<T>> requestWithRetry<T>(
    Future<Response<T>> Function() request, {
    int maxRetries = 3,
    Duration initialDelay = const Duration(seconds: 1),
  }) async {
    for (int i = 0; i < maxRetries; i++) {
      try {
        return await request();
      } catch (e) {
        if (i == maxRetries - 1) rethrow;
        await Future.delayed(initialDelay * (i + 1));
      }
    }
    throw Exception('Request failed after $maxRetries retries');
  }

  /// The underlying [Dio] instance used for all HTTP requests.
  /// Does NOT resolve the server base URL — call [ensureInitialized] first if needed.
  static Dio get dio {
    return _dio;
  }

  /// Ensures the server base URL is resolved via DNS or fallback IP.
  /// Safe to call multiple times; only performs initialization once.
  static Future<void> ensureInitialized() => _ensureInitialized();

  /// Overrides the base [url] used for all subsequent requests.
  static void setBaseUrl(String url) {
    _dio.options.baseUrl = url;
  }
}
