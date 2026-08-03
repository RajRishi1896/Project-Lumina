import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../core/services/activity_tracker.dart';
import '../../core/storage/db_helper.dart';
import 'download_service.dart';
import 'notification_service.dart';
import 'connectivity_service.dart';

/// An item waiting to be downloaded by [DownloadQueue].
class _QueuedDownload {
  final String resourceId;
  final String url;
  final String fileName;
  final String title;
  final String subject;
  final String grade;
  final String type;
  final double mtime;

  /// Remaining retry attempts before the download is abandoned (max 5).
  int retries = 5;

  _QueuedDownload(this.resourceId, this.url, this.fileName, {
    this.title = '',
    this.subject = '',
    this.grade = '',
    this.type = '',
    this.mtime = 0,
  });
}

/// Singleton queue that manages sequential file downloads with offline support.
///
/// When online, downloads are processed one at a time. When offline, items are
/// persisted to a pending-download table via [DownloadService] and flushed
/// automatically once connectivity is restored. Extends [ChangeNotifier] so
/// the UI can observe queue state changes.
class DownloadQueue extends ChangeNotifier {
  static final DownloadQueue _instance = DownloadQueue._internal();
  factory DownloadQueue() => _instance;
  DownloadQueue._internal();

  final List<_QueuedDownload> _queue = [];
  bool _processing = false;

  /// The set of resource IDs currently in the queue.
  Set<String> get queuedIds => _queue.map((d) => d.resourceId).toSet();

  /// The resource ID currently being downloaded, or `null` if idle.
  String? get active => _processing && _queue.isNotEmpty ? _queue.first.resourceId : null;

  /// Whether a download for [id] is already in the queue.
  bool contains(String id) => _queue.any((d) => d.resourceId == id);

  /// Adds a download to the queue.
  ///
  /// When online the item is queued in-memory and processed immediately.
  /// When offline it is persisted via [DownloadService.addPendingDownload]
  /// for later flushing. Duplicate [resourceId] values are ignored.
  Future<void> enqueue(String resourceId, String url, String fileName, {
    String title = '',
    String subject = '',
    String grade = '',
    String type = '',
    double mtime = 0,
  }) async {
    if (_queue.any((d) => d.resourceId == resourceId)) return;
    if (ConnectivityService().isOnline) {
      _queue.add(_QueuedDownload(resourceId, url, fileName,
        title: title, subject: subject, grade: grade, type: type, mtime: mtime));
      notifyListeners();
      if (!_processing) unawaited(_processNext());
    } else {
      await DBHelper().addPendingDownload(resourceId, url, fileName,
        title: title, subject: subject, grade: grade, type: type, mtime: mtime);
      notifyListeners();
    }
  }

  Future<void> _processNext() async {
    if (_queue.isEmpty) return;
    if (!_processing) {
      try { await WakelockPlus.enable(); } catch (_) {}
      try {
        final service = FlutterBackgroundService();
        final isRunning = await service.isRunning();
        if (!isRunning) await service.startService();
      } catch (_) {
        // ponytail: background service is best-effort; download still works in foreground
      }
    }
    _processing = true;

    final task = _queue.first;
    final notifId = task.resourceId.hashCode;
    String? path;
    try {
      path = await DownloadService().downloadAndTrack(
        task.resourceId, task.url, task.fileName,
        title: task.title, subject: task.subject, grade: task.grade,
        type: task.type, mtime: task.mtime,
        onProgress: (received, total) {
          if (total > 0 && _progressNotifThrottle.elapsed >= const Duration(milliseconds: 500)) {
            _progressNotifThrottle.reset();
            final pct = received * 100 ~/ total;
            NotificationService().showDownloadProgress(task.title, pct, id: notifId);
          }
        },
      );
      _lastErrorIsPermanent = false;
    } catch (e) {
      _lastErrorIsPermanent = e.toString().contains('STORAGE_FULL');
      path = null;
    }
    try { await NotificationService().cancelProgressNotification(notifId); } catch (_) {}
    if (path != null) {
      try { await DBHelper().removePendingDownload(task.resourceId); } catch (_) {}
      if (task.title.isNotEmpty) {
        unawaited(NotificationService().showDownloadComplete(task.title).catchError((_) {}));
      }
      unawaited(ActivityTracker().logAction('download', resourceId: task.resourceId, metadata: task.title).catchError((_) {}));
      _queue.removeAt(0);
      if (_queue.isEmpty) {
        try { await WakelockPlus.disable(); } catch (_) {}
        _processing = false;
        _stopBackgroundServiceIfIdle();
      }
      notifyListeners();
      if (_queue.isNotEmpty) unawaited(_processNext());
    } else if (task.retries > 0 && !_lastErrorIsPermanent) {
      task.retries--;
      debugPrint('DownloadQueue: retrying ${task.resourceId} (${task.retries} attempts left)');
      final retryCount = 5 - task.retries;
      final delay = Duration(seconds: 3 * (1 << retryCount));
      await Future.delayed(delay);
      unawaited(_processNext());
    } else {
      try { await DBHelper().removePendingDownload(task.resourceId); } catch (_) {}
      if (task.title.isNotEmpty) {
        unawaited(NotificationService().showDownloadFailed(task.title).catchError((_) {}));
      }
      _queue.removeAt(0);
      if (_queue.isEmpty) {
        try { await WakelockPlus.disable(); } catch (_) {}
        _processing = false;
        _stopBackgroundServiceIfIdle();
      }
      notifyListeners();
      if (_queue.isNotEmpty) unawaited(_processNext());
    }
  }

  bool _lastErrorIsPermanent = false;

  final Stopwatch _progressNotifThrottle = Stopwatch()..start();

  void _stopBackgroundServiceIfIdle() {
    if (_queue.isEmpty && !_processing) {
      try {
        final service = FlutterBackgroundService();
        service.isRunning().then((running) {
          if (running) service.invoke('stop');
        });
      } catch (_) {
        // ponytail: best-effort stop; service may not have started
      }
    }
  }
}
