import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/auth/data/auth_service.dart';

/// A singleton HTTP client wrapper around [Dio] that handles server discovery,
/// token-based authentication, and automatic retry on 401/403 responses.
class ApiClient {
  static const String _defaultDomain = 'http://lumina.hub:8000';
  static String _baseUrl = _defaultDomain;
  static bool _initialized = false;
  static Completer<void>? _refreshCompleter;

  /// Callback invoked when a token refresh fails and the user must be logged out.
  static void Function()? onForceLogout;

  static final Dio _dio = _createDio();

  static Dio _createDio() {
    final dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 10),
    ));
    if (kDebugMode) dio.interceptors.add(LogInterceptor());
    dio.interceptors.add(InterceptorsWrapper(
      onError: (error, handler) async {
        if (error.response?.statusCode == 401 || error.response?.statusCode == 403) {
          if (_refreshCompleter != null) {
            await _refreshCompleter!.future;
            final newToken = await AuthService().getSessionToken();
            error.requestOptions.headers['Authorization'] = 'Bearer $newToken';
            try {
              final retryResponse = await dio.fetch(error.requestOptions);
              handler.resolve(retryResponse);
              return;
            } catch (_) { }
            handler.next(error);
            return;
          }
          _refreshCompleter = Completer<void>();
          try {
            if (await AuthService().refreshSession()) {
              final newToken = await AuthService().getSessionToken();
              error.requestOptions.headers['Authorization'] = 'Bearer $newToken';
              try {
                final retryResponse = await dio.fetch(error.requestOptions);
                handler.resolve(retryResponse);
                return;
              } catch (_) { } }
            if (await AuthService().renewSession()) {
              final newToken = await AuthService().getSessionToken();
              error.requestOptions.headers['Authorization'] = 'Bearer $newToken';
              try {
                final retryResponse = await dio.fetch(error.requestOptions);
                handler.resolve(retryResponse);
                return;
              } catch (_) { } }
            await AuthService().logout();
            onForceLogout?.call();
          } finally {
            _refreshCompleter!.complete();
            _refreshCompleter = null;
          }
        }
        handler.next(error);
      },
    ));
    return dio;
  }

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

  static Future<void> _ensureInitialized() async {
    _configureKeepAlive();
    if (_initialized) return;
    await _doInitialize();
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
    } catch (e) {
      debugPrint('ApiClient initialization error: $e');
      _dio.options.baseUrl = _baseUrl;
      _initialized = true;
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
  
  /// The underlying [Dio] instance used for all HTTP requests.
  /// Does NOT resolve the server base URL -- call [ensureInitialized] first if needed.
  static Dio get dio {
    return _dio;
  }

  /// The resolved server base URL (e.g. `http://lumina.hub:8000`).
  static String get baseUrl => _baseUrl;

  /// Ensures the server base URL is resolved via DNS or fallback IP.
  /// Safe to call multiple times; only performs initialization once.
  static Future<void> ensureInitialized() => _ensureInitialized();

}
