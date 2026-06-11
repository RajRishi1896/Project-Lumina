import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../core/network/api_client.dart';
import '../../core/services/mutation_queue.dart';
import '../../core/services/catalog_service.dart';
import 'download_service.dart';
import 'download_queue.dart';

/// Singleton service that monitors network connectivity to the Lumina hub.
///
/// Uses [connectivity_plus] for platform-level connectivity events and a
/// periodic HTTP `/ping` heartbeat to confirm the server is reachable.
/// Extends [ChangeNotifier] so widgets can listen for online/offline transitions.
class ConnectivityService extends ChangeNotifier {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  bool _online = false;
  Timer? _heartbeatTimer;
  StreamSubscription<List<ConnectivityResult>>? _platformSub;

  /// Whether the server is currently reachable (both platform and HTTP).
  bool get isOnline => _online;

  /// Starts connectivity monitoring with platform listeners and a 30-second
  /// heartbeat timer. Automatically flushes the pending download queue when
  /// connectivity is restored.
  void start() {
    _heartbeatTimer?.cancel();
    _platformSub?.cancel();

    _platformSub = Connectivity().onConnectivityChanged.listen((results) {
      _lastPlatformResult = results;
      final hasConnection = results.any((r) => r != ConnectivityResult.none);
      if (hasConnection) {
        _checkNow();
      } else {
        _setOffline();
      }
    });

    _checkNow();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_platformHasConnectivity()) {
        _checkNow();
      }
    });
  }

  /// Stops all connectivity monitoring and cancels timers.
  void stop() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _platformSub?.cancel();
    _platformSub = null;
  }

  bool _platformHasConnectivity() {
    return _lastPlatformResult?.any((r) => r != ConnectivityResult.none) ?? true;
  }

  List<ConnectivityResult>? _lastPlatformResult;

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
        _flushPending();
      }
    } else if (_online) {
      _flushPending();
    }
  }

  Future<void> _flushPending() async {
    final items = await DownloadService().getAllPendingDownloads();
    if (items.isNotEmpty) {
      for (final item in items) {
        DownloadQueue().enqueue(
          item['resource_id'] as String,
          item['url'] as String,
          item['file_name'] as String,
          title: item['title'] as String? ?? '',
          subject: item['subject'] as String? ?? '',
          grade: item['grade'] as String? ?? '',
          type: item['type'] as String? ?? '',
          mtime: (item['mtime'] as num?)?.toDouble() ?? 0,
        );
      }
      await DownloadService().clearAllPendingDownloads();
    }
    await MutationQueue().flush();
    await CatalogService().syncCatalog();
  }

  /// Performs a single connectivity check against the server.
  Future<void> check() => _checkNow();
}
