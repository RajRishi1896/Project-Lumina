import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:pointycastle/export.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/auth/data/auth_service.dart';

/// A singleton HTTP client wrapper around [Dio] that handles server discovery,
/// token-based authentication, and automatic retry on 401/403 responses.
///
/// ## Encryption flow
/// Outgoing POST/PUT request bodies are encrypted with AES-256-GCM when an
/// encryption key is available. Responses containing `{"encrypted": "..."}`
/// are automatically decrypted. Authentication handshakes (`/register`,
/// `/student/token`) are never encrypted — they bootstrap the encryption key.
class ApiClient {
  /// Paths that must always be sent in plaintext (mirrors server's NO_ENCRYPT_PATHS).
  /// These bootstrap the encryption key or serve unauthenticated content.
  static const Set<String> _noEncryptPaths = {
    '/register', '/student/token', '/student/refresh-token',
    '/student/renew-session', '/ping', '/api/health',
  };

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
      onRequest: (options, handler) async {
        // Skip encryption for auth handshakes — key isn't available yet
        // or the server expects plaintext for these paths.
        final path = options.path;
        final noEncrypt = _noEncryptPaths.any((p) => path.startsWith(p));
        if (!noEncrypt && (options.method == 'POST' || options.method == 'PUT')) {
          try {
            final encKey = await AuthService().getEncryptionKey();
            if (encKey != null && encKey.isNotEmpty && options.data != null) {
              final bodyData = options.data is Map<String, dynamic>
                  ? options.data as Map<String, dynamic>
                  : jsonDecode(jsonEncode(options.data)) as Map<String, dynamic>;
              options.data = await encryptRequest(bodyData, encKey);
            }
          } catch (_) {}
        }
        handler.next(options);
      },
      onResponse: (response, handler) async {
        if (response.data is Map && (response.data as Map).containsKey('encrypted')) {
          try {
            final encKey = await AuthService().getEncryptionKey();
            if (encKey != null && encKey.isNotEmpty) {
              final decrypted = await decryptResponse(response.data as Map<String, dynamic>, encKey);
              response.data = decrypted;
            }
          } catch (_) {}
        }
        handler.next(response);
      },
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
              } catch (_) {}
            }
            if (await AuthService().renewSession()) {
              final newToken = await AuthService().getSessionToken();
              error.requestOptions.headers['Authorization'] = 'Bearer $newToken';
              try {
                final retryResponse = await _dio.fetch(error.requestOptions);
                handler.resolve(retryResponse);
                return;
              } catch (_) {}
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

  // ---- AES-256-GCM encryption helpers ----

  static Uint8List _aesGcmEncrypt(Uint8List plaintext, Uint8List key) {
    final random = Random.secure();
    final nonce = Uint8List(12);
    for (var i = 0; i < 12; i++) {
      nonce[i] = random.nextInt(256);
    }

    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(
        KeyParameter(key),
        128,
        nonce,
        Uint8List(0),
      ));

    final out = Uint8List(cipher.getOutputSize(plaintext.length));
    var len = cipher.processBytes(plaintext, 0, plaintext.length, out, 0);
    len += cipher.doFinal(out, len);

    final result = Uint8List(12 + len);
    result.setAll(0, nonce);
    result.setAll(12, out.sublist(0, len));
    return result;
  }

  static Uint8List _aesGcmDecrypt(Uint8List encrypted, Uint8List key) {
    final nonce = encrypted.sublist(0, 12);
    final ct = encrypted.sublist(12);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(
        KeyParameter(key),
        128,
        nonce,
        Uint8List(0),
      ));

    final out = Uint8List(cipher.getOutputSize(ct.length));
    var len = cipher.processBytes(ct, 0, ct.length, out, 0);
    try {
      len += cipher.doFinal(out, len);
    } catch (e) {
      throw Exception('Decryption failed: $e');
    }
    return out.sublist(0, len);
  }

  /// Encrypts a JSON-serializable map into the encrypted wrapper format.
  /// Returns a Map with `{"encrypted": "<base64>"}` ready for POST body.
  static Future<Map<String, dynamic>> encryptRequest(Map<String, dynamic> data, String encryptionKeyBase64) async {
    final key = base64.decode(encryptionKeyBase64);
    final jsonBytes = utf8.encode(jsonEncode(data));
    final encrypted = _aesGcmEncrypt(Uint8List.fromList(jsonBytes), Uint8List.fromList(key));
    return {'encrypted': base64.encode(encrypted)};
  }

  /// Decrypts the `{"encrypted": "<base64>"}` response body into a Map.
  static Future<Map<String, dynamic>> decryptResponse(Map<String, dynamic> encryptedWrapper, String encryptionKeyBase64) async {
    final key = base64.decode(encryptionKeyBase64);
    final raw = base64.decode(encryptedWrapper['encrypted'] as String);
    final decrypted = _aesGcmDecrypt(Uint8List.fromList(raw), Uint8List.fromList(key));
    return jsonDecode(utf8.decode(decrypted)) as Map<String, dynamic>;
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

  /// The resolved server base URL (e.g. `http://lumina.hub:8000`).
  static String get baseUrl => _baseUrl;

  /// Ensures the server base URL is resolved via DNS or fallback IP.
  /// Safe to call multiple times; only performs initialization once.
  static Future<void> ensureInitialized() => _ensureInitialized();

  /// Overrides the base [url] used for all subsequent requests.
  static void setBaseUrl(String url) {
    _dio.options.baseUrl = url;
  }
}
