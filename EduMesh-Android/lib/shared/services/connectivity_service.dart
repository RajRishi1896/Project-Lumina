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

  bool _online = false;
  StreamSubscription<List<ConnectivityResult>>? _platformSub;

  /// Whether the server is currently reachable (both platform and HTTP).
  bool get isOnline => _online;

  /// Starts connectivity monitoring with platform listeners.
  void start() {
    _platformSub?.cancel();

    _platformSub = Connectivity().onConnectivityChanged.listen((results) {
      final hasConnection = results.any((r) => r != ConnectivityResult.none);
      if (hasConnection) {
        _checkNow();
      } else {
        _setOffline();
      }
    });

    _checkNow();
  }

  /// Stops all connectivity monitoring and cancels timers.
  void stop() {
    _platformSub?.cancel();
    _platformSub = null;
  }

  void _setOffline() {
    final wasOnline = _online;
    _online = false;
    if (_online != wasOnline) {
      notifyListeners();
    }
  }

  Future<void> _checkNow() async {
    final wasOnline = _online;
    try {
      await ApiClient.ensureInitialized();
      await ApiClient.dio.get('/ping', options: Options(
        sendTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 4),
      ));
      _online = true;
    } catch (_) {
      _online = false;
    }
    if (_online != wasOnline) {
      notifyListeners();
      if (_online) {
        unawaited(_flushPending());
      }
    } else if (_online) {
      unawaited(_flushPending());
    }
  }

  Future<void> _flushPending() async {
    final items = await DBHelper().getAllPendingDownloads();
    if (items.isNotEmpty) {
      for (final item in items) {
        unawaited(DownloadQueue().enqueue(
          item['resource_id'] as String,
          item['url'] as String,
          item['file_name'] as String,
          title: item['title'] as String? ?? '',
          subject: item['subject'] as String? ?? '',
          grade: item['grade'] as String? ?? '',
          type: item['type'] as String? ?? '',
          mtime: (item['mtime'] as num?)?.toDouble() ?? 0,
        ));
      }
      await DBHelper().clearAllPendingDownloads();
    }
    await MutationQueue().flush();
    await CatalogService().syncCatalog();
    await CatalogService().syncSimilarCourses();
  }

  /// Performs a single connectivity check against the server.
  Future<void> check() => _checkNow();

  /// Pings the server's `/ping` endpoint and returns whether it responded with 2xx.
  Future<bool> ping({Duration timeout = const Duration(seconds: 10)}) async {
    final cancelToken = CancelToken();
    try {
      await ApiClient.ensureInitialized();
      final resp = await ApiClient.get('/ping', cancelToken: cancelToken).timeout(timeout);
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
