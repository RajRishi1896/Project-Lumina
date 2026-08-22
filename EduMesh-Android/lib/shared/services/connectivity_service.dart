import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/db_helper.dart';
import '../../core/services/mutation_queue.dart';
import '../../core/services/catalog_service.dart';
import 'download_queue.dart';

/// Singleton service that monitors network connectivity to the Lumina hub.
///
/// Uses [connectivity_plus] for platform-level connectivity events.
/// Extends [ChangeNotifier] so widgets can listen for online/offline transitions.
class ConnectivityService extends ChangeNotifier {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  // Fail-open: assume online until the first FAILED ping proves otherwise.
  // Starting at false left taps dead for the first seconds after launch even
  // though catalog loads via Dio succeeded.
  bool _online = true;
  int _checkSeq = 0;
  bool _startupFlushed = false;
  StreamSubscription<List<ConnectivityResult>>? _platformSub;
  Timer? _heartbeat;
  static const String _pingPath = '/ping';

  /// Whether the server is currently reachable (both platform and HTTP).
  bool get isOnline => _online;

  /// Starts connectivity monitoring with platform listeners.
  void start() {
    _platformSub?.cancel();
    _heartbeat?.cancel();

    _platformSub = Connectivity().onConnectivityChanged.listen((results) {
      final hasConnection = results.any((r) => r != ConnectivityResult.none);
      if (hasConnection) {
        _checkNow();
      } else {
        _setOffline();
      }
    });

    _checkNow();
    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) => _checkNow());
  }

  void _setOffline() {
    _checkSeq++;
    final wasOnline = _online;
    _online = false;
    if (_online != wasOnline) {
      notifyListeners();
    }
  }

  Future<void> _checkNow() async {
    final mySeq = ++_checkSeq;
    final wasOnline = _online;
    try {
      await ApiClient.ensureInitialized();
      await ApiClient.dio.get(_pingPath, options: Options(
        sendTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 4),
      ));
      if (mySeq != _checkSeq) return;
      _online = true;
      if (!_startupFlushed) {
        // Cold start while already online: no offline->online transition
        // will ever fire (because _online starts true), so flush the
        // queued mutations and pending downloads once, right after the
        // first confirmed ping.
        _startupFlushed = true;
        unawaited(ApiClient.maybeReResolve());
        unawaited(_flushPending());
      }
    } catch (_) {
      if (mySeq != _checkSeq) return;
      _online = false;
    }
    if (_online != wasOnline) {
      notifyListeners();
      if (_online) {
        unawaited(ApiClient.maybeReResolve());
        unawaited(_flushPending());
      }
    }
  }

  Future<void> _flushPending() async {
    final items = await DBHelper().getAllPendingDownloads();
    if (items.isNotEmpty) {
      for (final item in items) {
        try {
          await DownloadQueue().enqueue(
            item['resource_id'] as String,
            item['url'] as String,
            item['file_name'] as String,
            title: item['title'] as String? ?? '',
            subject: item['subject'] as String? ?? '',
            grade: item['grade'] as String? ?? '',
            type: item['type'] as String? ?? '',
            mtime: (item['mtime'] as num?)?.toDouble() ?? 0,
          );
        } catch (_) {}
      }
    }
    try {
      await MutationQueue().flush();
    } catch (_) {}
    try {
      await CatalogService().syncCatalog();
    } catch (_) {}
    try {
      await CatalogService().syncSimilarCourses();
    } catch (_) {}
  }

  /// Pings the server's `/ping` endpoint and returns whether it responded with 2xx.
  Future<bool> ping({Duration timeout = const Duration(seconds: 10)}) async {
    final cancelToken = CancelToken();
    try {
      await ApiClient.ensureInitialized();
      final resp = await ApiClient.get(_pingPath, cancelToken: cancelToken).timeout(timeout);
      return resp.statusCode != null && resp.statusCode! >= 200 && resp.statusCode! < 300;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return false;
      return false;
    } on TimeoutException catch (_) {
      cancelToken.cancel('Timeout');
      return false;
    } catch (_) {
      return false;
    }
  }
}
