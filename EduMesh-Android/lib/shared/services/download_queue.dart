import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../core/services/activity_tracker.dart';
import '../../core/storage/db_helper.dart';
import 'download_service.dart';
import 'notification_service.dart';
import 'connectivity_service.dart';
import 'share_server.dart';

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

  Set<String> get queuedIds => _queue.map((d) => d.resourceId).toSet();

  /// Drops every queued download.
  ///
  /// Called on logout/profile switch so one student's pending downloads never
  /// run under another student's session.
  // ponytail: an in-flight download may still complete; full cancellation
  // needs a CancelToken threaded through DownloadService.
  void clear() {
    _queue.clear();
    _processing = false;
    // Best-effort cleanup: logout/profile switch must not leak the CPU
    // wakelock or leave the foreground service running between profiles.
    WakelockPlus.disable().ignore();
    unawaited(_stopBackgroundServiceIfIdle());
    notifyListeners();
  }

  /// The resource ID currently being downloaded, or `null` if idle.
  String? get active => _processing && _queue.isNotEmpty ? _queue.first.resourceId : null;

  bool contains(String id) => _queue.any((d) => d.resourceId == id);

  /// Adds a download to the queue.
  ///
  /// The item is always persisted to the pending-download table so an in-flight
  /// queue survives an app restart. When online it is also processed
  /// immediately; when offline it is left for [ConnectivityService] to re-queue
  /// on reconnect. Rows whose resource is already recorded as downloaded are
  /// dropped instead of being re-downloaded. Duplicate [resourceId] values are
  /// ignored.
  Future<void> enqueue(String resourceId, String url, String fileName, {
    String title = '',
    String subject = '',
    String grade = '',
    String type = '',
    double mtime = 0,
  }) async {
    if (_queue.any((d) => d.resourceId == resourceId)) return;
    final downloadedIds = await DBHelper().getDownloadedIds();
    if (downloadedIds.contains(resourceId)) {
      await DBHelper().removePendingDownload(resourceId);
      return;
    }
    await DBHelper().addPendingDownload(resourceId, url, fileName,
      title: title, subject: subject, grade: grade, type: type, mtime: mtime);
    if (ConnectivityService().isOnline) {
      _queue.add(_QueuedDownload(resourceId, url, fileName,
        title: title, subject: subject, grade: grade, type: type, mtime: mtime));
      notifyListeners();
      if (!_processing) unawaited(_processNext());
    } else {
      notifyListeners();
    }
  }

  /// Drains the queue sequentially.
  ///
  /// [_processing] is set synchronously before any await so two rapid
  /// enqueues can never both pass the `!_processing` check and spawn
  /// duplicate loops.
  Future<void> _processNext() async {
    if (_processing) return;
    _processing = true;
    final service = FlutterBackgroundService();
    try { await WakelockPlus.enable(); } catch (_) {}
    try {
      final isRunning = await service.isRunning();
      if (!isRunning) await service.startService();
    } catch (_) {
      // ponytail: background service is best-effort; download still works in foreground
    }

    while (_queue.isNotEmpty) {
      final task = _queue.first;
      String? path;
      try {
        // Reset the isolate-side percent: a finished download leaves 100%
        // displayed while this one sits at 0.
        service.invoke('progress', {'percent': 0});
        // downloadFile (not downloadAndTrack) so the error type survives for
        // permanent-failure classification; tracking is replicated below.
        final file = await DownloadService().downloadFile(
          task.url, task.fileName,
          onProgress: (received, total) {
            // The foreground-service notification is the single progress
            // indicator: forward the percent to the background isolate instead
            // of posting a second per-download notification.
            if (total > 0 && _progressThrottle.elapsed >= const Duration(milliseconds: 500)) {
              _progressThrottle.reset();
              service.invoke('progress', {'percent': received * 100 ~/ total});
            }
          },
        );
        if (file != null) {
          await DBHelper().insertDownload(task.resourceId, file.path, task.title, task.subject, task.grade, task.type, mtime: task.mtime);
          ShareServer().markIndexDirty();
          path = file.path;
        }
        _lastErrorIsPermanent = false;
      } catch (e) {
        _lastErrorIsPermanent = _isPermanentFailure(e);
        path = null;
      }
      if (path != null) {
        try { await DBHelper().removePendingDownload(task.resourceId); } catch (_) {}
        if (task.title.isNotEmpty) {
          unawaited(NotificationService().showDownloadComplete(task.title).catchError((_) {}));
        }
        unawaited(ActivityTracker().logAction('download', resourceId: task.resourceId, metadata: task.title).catchError((_) {}));
        _queue.removeAt(0);
      } else if (task.retries > 0 && !_lastErrorIsPermanent) {
        task.retries--;
        debugPrint('DownloadQueue: retrying ${task.resourceId} (${task.retries} attempts left)');
        final retryCount = 5 - task.retries;
        await Future.delayed(Duration(seconds: 3 * (1 << retryCount)));
        continue; // same task stays at the head
      } else {
        try { await DBHelper().removePendingDownload(task.resourceId); } catch (_) {}
        if (task.title.isNotEmpty) {
          unawaited(NotificationService().showDownloadFailed(task.title).catchError((_) {}));
        }
        _queue.removeAt(0);
      }
      notifyListeners();
    }

    try { await WakelockPlus.disable(); } catch (_) {}
    _processing = false;
    notifyListeners();
    unawaited(_stopBackgroundServiceIfIdle());
  }

  bool _lastErrorIsPermanent = false;

  final Stopwatch _progressThrottle = Stopwatch()..start();

  /// Whether [error] can never succeed on retry: missing/forbidden resource,
  /// a range-resume the server rejected, empty response body, or full storage.
  /// Only network and unknown errors go through the retry loop.
  bool _isPermanentFailure(Object error) {
    return error is DownloadError && switch (error.code) {
      DownloadErrorCode.notFound ||
      DownloadErrorCode.forbidden ||
      DownloadErrorCode.rangeNotSupported ||
      DownloadErrorCode.storageFull ||
      DownloadErrorCode.emptyResponse => true,
      _ => false,
    };
  }

  Future<void> _stopBackgroundServiceIfIdle() async {
    if (_queue.isNotEmpty || _processing) return;
    try {
      final service = FlutterBackgroundService();
      // Retry: invoke('stop') can reach the isolate before its on('stop')
      // listener registers when a download fails right after start.
      for (var attempt = 0; attempt < 3; attempt++) {
        if (!await service.isRunning()) return;
        service.invoke('stop');
        await Future.delayed(const Duration(seconds: 3));
      }
    } catch (_) {
      // ponytail: best-effort stop; service may not have started
    }
  }
}
