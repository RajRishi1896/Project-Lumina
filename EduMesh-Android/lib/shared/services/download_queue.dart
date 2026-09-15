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

  /// Course-batch grouping: '' means ungrouped (legacy per-drain summary).
  final String groupId;
  final String groupTitle;

  /// Remaining retry attempts before the download is abandoned (max 5).
  int retries = 5;

  _QueuedDownload(this.resourceId, this.url, this.fileName, {
    this.title = '',
    this.subject = '',
    this.grade = '',
    this.type = '',
    this.mtime = 0,
    this.groupId = '',
    this.groupTitle = '',
  });
}

/// Verdict for a finished download group: [complete] when every task
/// succeeded, [failed] when at least one task failed.
enum GroupVerdict { complete, failed }

/// Pure per-group progress tracker behind [DownloadQueue]'s course-batch
/// notifications: one verdict per group when its last task settles.
///
/// Totals grow via [add] while the group drains, so tasks enqueued mid-drain
/// delay the verdict instead of being orphaned. No I/O, no notifications:
/// the queue maps a returned verdict to [NotificationService].
class DownloadGroupTracker {
  final Map<String, _GroupProgress> _groups = {};

  /// Number of groups with outstanding tasks.
  int get pendingGroupCount => _groups.length;

  /// Registers one more task in [groupId]. First non-empty title wins.
  void add(String groupId, String title) {
    final g = _groups.putIfAbsent(groupId, () => _GroupProgress(title));
    g.total++;
    if (g.title.isEmpty && title.isNotEmpty) g.title = title;
  }

  /// Records one settled task. Returns `(verdict, title)` exactly once, when
  /// the group's last outstanding task settles; otherwise null.
  (GroupVerdict, String)? settle(String groupId, {required bool success}) {
    final g = _groups[groupId];
    if (g == null) return null;
    if (success) {
      g.done++;
    } else {
      g.failed++;
    }
    if (g.done + g.failed >= g.total) {
      _groups.remove(groupId);
      return (g.failed > 0 ? GroupVerdict.failed : GroupVerdict.complete, g.title);
    }
    return null;
  }

  /// Drops one unsettled task (user cancel). Returns a verdict when the
  /// remaining tasks have all settled, else null. A group left empty before
  /// anything settled is removed silently: nothing to report.
  (GroupVerdict, String)? discard(String groupId) {
    final g = _groups[groupId];
    if (g == null) return null;
    g.total--;
    if (g.total <= 0) {
      _groups.remove(groupId);
      return null;
    }
    if (g.done + g.failed >= g.total && g.done + g.failed > 0) {
      _groups.remove(groupId);
      return (g.failed > 0 ? GroupVerdict.failed : GroupVerdict.complete, g.title);
    }
    return null;
  }

  /// Drops all groups without verdicts (logout/profile switch).
  void clear() => _groups.clear();
}

class _GroupProgress {
  String title;
  int total = 0;
  int done = 0;
  int failed = 0;
  _GroupProgress(this.title);
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

  /// In-memory progress of grouped (course-batch) downloads.
  final DownloadGroupTracker _groups = DownloadGroupTracker();

  /// True when the queue halted because the hub went unreachable
  /// mid-download. Retries are preserved; the loop restarts on reconnect.
  bool _paused = false;

  /// Whether the queue is paused waiting for the hub to come back.
  bool get isPaused => _paused;

  Set<String> get queuedIds => _queue.map((d) => d.resourceId).toSet();

  /// Display titles of the in-memory queued items, keyed by resource ID.
  /// Empty when the caller enqueued without a title.
  Map<String, String> get queuedTitles =>
      {for (final d in _queue) d.resourceId: d.title};

  /// Drops every queued download.
  ///
  /// Called on logout/profile switch so one student's pending downloads never
  /// run under another student's session.
  // ponytail: an in-flight download may still complete; full cancellation
  // needs a CancelToken threaded through DownloadService.
  void clear() {
    _queue.clear();
    _groups.clear();
    _processing = false;
    _paused = false;
    // Best-effort cleanup: logout/profile switch must not leak the CPU
    // wakelock or leave the foreground service running between profiles.
    WakelockPlus.disable().ignore();
    unawaited(_stopBackgroundServiceIfIdle());
    notifyListeners();
  }

  /// Cancels a single queued download by resource ID.
  ///
  /// If the item is currently being downloaded it will complete but not retry;
  /// pending items are removed from queue and DB.
  Future<void> cancel(String resourceId) async {
    var groupId = '';
    for (final d in _queue) {
      if (d.resourceId == resourceId) {
        groupId = d.groupId;
        break;
      }
    }
    _queue.removeWhere((d) => d.resourceId == resourceId);
    await DBHelper().removePendingDownload(resourceId);
    if (groupId.isNotEmpty) {
      final verdict = _groups.discard(groupId);
      if (verdict != null) _notifyGroupVerdict(verdict);
    }
    notifyListeners();
    if (_queue.isEmpty) {
      _processing = false;
      try { await WakelockPlus.disable(); } catch (_) {}
      unawaited(_stopBackgroundServiceIfIdle());
    }
  }

  /// Restarts the loop after a pause (reconnect). No-op unless paused
  /// with work remaining. Needed because [enqueue] dedupes tasks already
  /// in memory, so a paused head would otherwise never resume.
  void resumeIfPaused() {
    if (!_paused || _processing || _queue.isEmpty) return;
    unawaited(_processNext());
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
  ///
  /// A non-empty [groupId] batches the task into a course download: grouped
  /// tasks post no individual notification and instead contribute to one
  /// group verdict ([NotificationService.showDownloadComplete] with
  /// [groupTitle] when all succeed, `showDownloadFailed` otherwise) once the
  /// group's last task settles. '' keeps the legacy ungrouped behavior.
  Future<void> enqueue(String resourceId, String url, String fileName, {
    String title = '',
    String subject = '',
    String grade = '',
    String type = '',
    double mtime = 0,
    String groupId = '',
    String groupTitle = '',
  }) async {
    if (_queue.any((d) => d.resourceId == resourceId)) return;
    final downloadedIds = await DBHelper().getDownloadedIds();
    if (downloadedIds.contains(resourceId)) {
      await DBHelper().removePendingDownload(resourceId);
      return;
    }
    await DBHelper().addPendingDownload(resourceId, url, fileName,
      title: title, subject: subject, grade: grade, type: type, mtime: mtime,
      groupId: groupId, groupTitle: groupTitle);
    if (ConnectivityService().isOnline) {
      if (groupId.isNotEmpty) _groups.add(groupId, groupTitle);
      _queue.add(_QueuedDownload(resourceId, url, fileName,
        title: title, subject: subject, grade: grade, type: type, mtime: mtime,
        groupId: groupId, groupTitle: groupTitle));
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
    _paused = false;
    final service = FlutterBackgroundService();
    try { await WakelockPlus.enable(); } catch (_) {}
    try {
      final isRunning = await service.isRunning();
      if (!isRunning) await service.startService();
    } catch (_) {
      // ponytail: background service is best-effort; download still works in foreground
    }

    int completedCount = 0;
    int failedCount = 0;
    int groupedCompleted = 0;
    String lastCompletedTitle = '';

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
        // Hub went away mid-download: pause instead of burning retries.
        // The task stays queued (and persisted) and resumes from its
        // .part offset on reconnect via Range. Permanent failures and
        // reachable-hub errors keep the existing retry/drop path below.
        if (!_lastErrorIsPermanent && await _hubUnreachable()) {
          _paused = true;
          notifyListeners();
          break;
        }
      }
      if (path != null) {
        try { await DBHelper().removePendingDownload(task.resourceId); } catch (_) {}
        _queue.removeAt(0);
        if (task.groupId.isEmpty) {
          completedCount++;
          lastCompletedTitle = task.title;
        } else {
          groupedCompleted++;
          final verdict = _groups.settle(task.groupId, success: true);
          if (verdict != null) _notifyGroupVerdict(verdict);
        }
      } else if (task.retries > 0 && !_lastErrorIsPermanent) {
        task.retries--;
        debugPrint('DownloadQueue: retrying ${task.resourceId} (${task.retries} attempts left)');
        final retryCount = 5 - task.retries;
        await Future.delayed(Duration(seconds: 3 * (1 << retryCount)));
        continue; // same task stays at the head
      } else {
        try { await DBHelper().removePendingDownload(task.resourceId); } catch (_) {}
        _queue.removeAt(0);
        if (task.groupId.isEmpty) {
          failedCount++;
        } else {
          final verdict = _groups.settle(task.groupId, success: false);
          if (verdict != null) _notifyGroupVerdict(verdict);
        }
      }
      notifyListeners();
    }

    // Single summary notification instead of per-item (ungrouped tasks only;
    // grouped tasks already produced exactly one verdict notification each).
    if (completedCount > 0 || failedCount > 0) {
      final msg = completedCount == 1
          ? lastCompletedTitle
          : completedCount > 1
              ? '$completedCount downloads complete'
              : '';
      if (msg.isNotEmpty) {
        unawaited(NotificationService().showDownloadComplete(msg).catchError((_) {}));
      }
      if (completedCount + groupedCompleted > 0) {
        final totalCompleted = completedCount + groupedCompleted;
        final activityMeta = completedCount == 1 && groupedCompleted == 0
            ? lastCompletedTitle
            : '$totalCompleted resources downloaded';
        unawaited(ActivityTracker().logAction('download', metadata: activityMeta).catchError((_) {}));
      }
      if (failedCount > 0) {
        unawaited(NotificationService().showDownloadFailed('$failedCount download${failedCount > 1 ? 's' : ''} failed').catchError((_) {}));
      }
    } else if (groupedCompleted > 0) {
      unawaited(ActivityTracker()
          .logAction('download', metadata: '$groupedCompleted resources downloaded')
          .catchError((_) {}));
    }

    try { await WakelockPlus.disable(); } catch (_) {}
    _processing = false;
    notifyListeners();
    unawaited(_stopBackgroundServiceIfIdle());
  }

  bool _lastErrorIsPermanent = false;

  /// Posts the single notification for a finished download group: complete
  /// when every task succeeded, failed otherwise. Reuses the existing
  /// per-download notification strings with the group (course) title.
  void _notifyGroupVerdict((GroupVerdict, String) fired) {
    final (verdict, title) = fired;
    if (verdict == GroupVerdict.complete) {
      unawaited(NotificationService().showDownloadComplete(title).catchError((_) {}));
    } else {
      unawaited(NotificationService().showDownloadFailed(title).catchError((_) {}));
    }
  }

  /// Whether the hub is currently unreachable (short ping, not the
  /// possibly-stale cached connectivity flag, which can lag ~30s).
  Future<bool> _hubUnreachable() async {
    try {
      return !await ConnectivityService()
          .ping(timeout: const Duration(seconds: 3));
    } catch (_) {
      return true;
    }
  }

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
