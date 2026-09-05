import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/auth/data/auth_service.dart';

/// A singleton HTTP client wrapper around [Dio] that handles server discovery,
/// token-based authentication, and automatic retry on 401/403 responses.
class ApiClient {
  static const String _defaultDomain = 'http://127.0.0.1:8000';

  /// Standard Android hotspot gateway IP — last-resort fallback when mDNS
  /// and loopback discovery both fail (typical when phone connects to hub WiFi).
  static const String _gatewayFallback = 'http://10.42.0.1:8000';
  // ponytail: compiled once; fileBaseUrl is called per URL construction.
  static final RegExp _apiSuffixRe = RegExp(r'/api/?$');
  static String _baseUrl = _defaultDomain;
  static bool _initialized = false;
  static Completer<void>? _initCompleter;
  static Completer<void>? _refreshCompleter;

  /// Callback invoked when a token refresh fails and the user must be logged out.
  static void Function()? onForceLogout;

  /// Local-only teardown on an unrecoverable 401: clears credentials and
  /// per-profile state without a network call, so it cannot re-enter this
  /// interceptor and deadlock.
  static Future<void> _forceLogoutLocal() async {
    try { await AuthService().logoutLocal(); } catch (_) {}
    onForceLogout?.call();
  }

  /// Monotonic session-generation counter from [AuthService]: bumped on
  /// every logout/profile switch. Background services snapshot it at start
  /// and re-check before writing per-profile data.
  static int get sessionGeneration => AuthService.sessionGeneration;

  static final Dio _dio = _createDio();

  static Dio _createDio() {
    final dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 15),
    ));
    if (kDebugMode) dio.interceptors.add(LogInterceptor());
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        options.extra['lumina_gen'] = AuthService.sessionGeneration;
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          final path = error.requestOptions.path;
          // Auth/logout endpoints must bypass the refresh queue: a 401 on
          // /logout re-entering this interceptor would await the completer
          // held by the very logout that triggered it (circular await).
          if (path.endsWith('/student/token') || path.endsWith('/token') || path.endsWith('/register') || path.endsWith('/student/refresh-token') || path.endsWith('/student/renew-session') || path.endsWith('/logout')) {
            handler.next(error);
            return;
          }
          if (error.requestOptions.extra['lumina_retried'] == true) {
            await _forceLogoutLocal();
            handler.next(error);
            return;
          }
          if (_refreshCompleter != null) {
            try {
              // ponytail: 8s cap so a deadlocked refresh degrades to
              // force-logout instead of freezing the caller forever.
              await _refreshCompleter!.future.timeout(const Duration(seconds: 8));
            } catch (_) {
              await _forceLogoutLocal();
              handler.next(error);
              return;
            }
            // Profile switched (or logged out) while we waited on the
            // refresh completer. Whatever token is current belongs to
            // another student: retrying would send this request under it.
            // Surface the original 401 without triggering force-logout.
            if (AuthService.sessionGeneration != error.requestOptions.extra['lumina_gen']) {
              handler.next(error);
              return;
            }
            final newToken = await AuthService().getSessionToken();
            error.requestOptions.headers['Authorization'] = 'Bearer $newToken';
            error.requestOptions.extra['lumina_retried'] = true;
            try {
              final retryResponse = await dio.fetch(error.requestOptions);
              handler.resolve(retryResponse);
            } catch (_) {
              handler.next(error);
            }
            return;
          }
          _refreshCompleter = Completer<void>();
          try {
            try {
              // refreshSession already falls back to renewSession internally;
              // calling renewSession here too double-renews per 401.
              if (await AuthService().refreshSession()) {
                // Profile switched while this request was in flight or the
                // refresh was running: the fresh token belongs to another
                // student, so retrying would send it under their identity.
                if (AuthService.sessionGeneration != error.requestOptions.extra['lumina_gen']) {
                  handler.next(error);
                  return;
                }
                final newToken = await AuthService().getSessionToken();
                error.requestOptions.headers['Authorization'] = 'Bearer $newToken';
                error.requestOptions.extra['lumina_retried'] = true;
                try {
                  final retryResponse = await dio.fetch(error.requestOptions);
                  handler.resolve(retryResponse);
                } catch (_) {
                  handler.next(error);
                }
                return;
              }
            } catch (_) {}
            // Only tear down the session when it is still the one this
            // request belonged to. A refresh that bailed because another
            // profile switched in must not log THAT profile out.
            if (AuthService.sessionGeneration == error.requestOptions.extra['lumina_gen']) {
              await _forceLogoutLocal();
            }
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
    if (_initCompleter != null) {
      await _initCompleter!.future;
      return;
    }
    _initCompleter = Completer<void>();
    try {
      await _doInitialize();
    } finally {
      _initCompleter!.complete();
      _initCompleter = null;
    }
  }

  static const String _mdnsServiceType = '_http._tcp.local.';
  static const String _mdnsInstanceName = 'EduMeshHub';
  static const int _hubPort = 8000;

  /// Probes loopback addresses 127.0.0.1..127.0.0.255 for a listening hub
  /// and returns the first base URL that answers /ping, or null.
  ///
  /// Closed loopback ports fail fast (connection refused); a per-attempt
  /// timeout of 400ms covers silently-dropping firewalls, and a 10s overall
  /// budget bounds the whole sweep on slow devices.
  static Future<String?> _loopbackDiscover() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(milliseconds: 400);
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    try {
      for (var x = 1; x <= 255; x++) {
        if (DateTime.now().isAfter(deadline)) return null;
        final base = 'http://127.0.0.$x:$_hubPort';
        try {
          final req = await client
              .getUrl(Uri.parse('$base/ping'))
              .timeout(const Duration(milliseconds: 400));
          final res = await req.close().timeout(const Duration(milliseconds: 400));
          final ok = res.statusCode == 200;
          await res.drain<void>();
          if (ok) return base;
        } catch (_) {
          // Refused or timed out -> next candidate.
        }
      }
    } finally {
      client.close();
    }
    return null;
  }

  /// Looks up the hub via mDNS and returns its base URL.
  ///
  /// The hub advertises `EduMeshHub._http._tcp.local.` on port 8000. Returns
  /// `http://{ip}:8000`, or null if no hub is advertised, the lookup times
  /// out (4s), or multicast is unavailable.
  static Future<String?> _mdnsDiscover() async {    final client = MDnsClient();
    try {
      await client.start();
      final ptr = await client
          .lookup<PtrResourceRecord>(
              ResourceRecordQuery.serverPointer(_mdnsServiceType))
          .timeout(const Duration(seconds: 4))
          .firstWhere(
            (r) => r.domainName.startsWith('$_mdnsInstanceName.'),
            orElse: () => throw StateError('hub not advertised'),
          );
      final srv = await client
          .lookup<SrvResourceRecord>(ResourceRecordQuery.service(ptr.domainName))
          .timeout(const Duration(seconds: 4))
          .firstWhere(
            (r) => r.target.isNotEmpty,
            orElse: () => throw StateError('no SRV record'),
          );
      final ips = await client
          .lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(srv.target))
          .timeout(const Duration(seconds: 4))
          .toList();
      if (ips.isEmpty) return null;
      final best = ips.firstWhere(
        (r) => !r.address.isLinkLocal,
        orElse: () => ips.first,
      );
      return 'http://${best.address.address}:$_hubPort';
    } catch (_) {
      return null;
    } finally {
      client.stop();
    }
  }

  static Future<void> _doInitialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final fallbackIp = prefs.getString('server_fallback_ip');
        if (fallbackIp != null && fallbackIp.isNotEmpty) {
          _baseUrl = 'http://$fallbackIp:8000';
          debugPrint('ApiClient: Using fallback IP $fallbackIp');
        } else {
          final mdnsUrl = await _mdnsDiscover();
          if (mdnsUrl != null) {
            _baseUrl = mdnsUrl;
            debugPrint('ApiClient: mDNS discovered hub at $mdnsUrl');
            final host = Uri.tryParse(mdnsUrl)?.host;
            if (host != null && host.isNotEmpty) {
              await prefs.setString('server_fallback_ip', host);
            }
          } else {
            final loopback = await _loopbackDiscover();
            if (loopback != null) {
              _baseUrl = loopback;
              debugPrint('ApiClient: loopback discovered hub at $loopback');
              final host = Uri.tryParse(loopback)?.host;
              if (host != null && host.isNotEmpty) {
                await prefs.setString('server_fallback_ip', host);
              }
            } else {
              // Ponytail: gateway fallback. On hotspot WiFi the hub is at
              // 10.42.0.1; neither mDNS nor 127.0.0.x scan finds it.
              _baseUrl = _gatewayFallback;
              debugPrint('ApiClient: using gateway fallback $_gatewayFallback');
            }
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

  /// Sends a GET request returning raw bytes (for images, PDFs, etc.).
  /// The response [data] is [Uint8List] regardless of Content-Type.
  static Future<Response<Uint8List>> getBinary(String path, {Map<String, dynamic>? queryParameters, CancelToken? cancelToken}) async {
    await _ensureInitialized();
    return _dio.get<Uint8List>(path,
      queryParameters: queryParameters,
      cancelToken: cancelToken,
      options: Options(responseType: ResponseType.bytes),
    );
  }

  /// Sends a POST request to the given [path] with optional [data] and [queryParameters].
  /// Resolves the server base URL first via [_ensureInitialized].
  static Future<Response<T>> post<T>(String path, {dynamic data, Map<String, dynamic>? queryParameters}) async {
    await _ensureInitialized();
    return _dio.post<T>(path, data: data, queryParameters: queryParameters);
  }

  /// The underlying [Dio] instance used for all HTTP requests.
  /// Does NOT resolve the server base URL: call [ensureInitialized] first if needed.
  static Dio get dio {
    return _dio;
  }

  /// The resolved server base URL (e.g. `http://127.0.0.1:8000`).
  static String get baseUrl => _baseUrl;

  /// The server base URL with any trailing `/api` stripped, for file URLs.
  static String get fileBaseUrl => _baseUrl.replaceAll(_apiSuffixRe, '');

  /// Ensures the server base URL is resolved via DNS or fallback IP.
  /// Safe to call multiple times; only performs initialization once.
  static Future<void> ensureInitialized() => _ensureInitialized();

  /// If the current base URL is a raw fallback IP, re-runs mDNS discovery and
  /// switches back to an advertised hub address once one is found.
  /// Call on every connectivity restore.
  static Future<void> maybeReResolve() async {
    final uri = Uri.tryParse(_baseUrl);
    if (uri == null) return;
    if (InternetAddress.tryParse(uri.host) == null) return;
    final mdnsUrl = await _mdnsDiscover();
    if (mdnsUrl != null) {
      _baseUrl = mdnsUrl;
      _dio.options.baseUrl = _baseUrl;
      debugPrint('ApiClient: mDNS recovered, using advertised hub');
    }
  }

}
