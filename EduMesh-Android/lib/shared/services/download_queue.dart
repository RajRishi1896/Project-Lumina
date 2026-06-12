import 'package:flutter/foundation.dart';
import '../../core/services/activity_tracker.dart';
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
      if (!_processing) _processNext();
    } else {
      await DownloadService().addPendingDownload(resourceId, url, fileName,
        title: title, subject: subject, grade: grade, type: type, mtime: mtime);
      notifyListeners();
    }
  }

  /// Updates [active] state after a task completes or is removed, and notifies
  /// listeners so the UI can react to queue changes.
  void _finishTask() {
    _processing = _queue.isNotEmpty;
    notifyListeners();
  }

  Future<void> _processNext() async {
    if (_queue.isEmpty) return;
    _processing = true;

    final task = _queue.first;
    final path = await DownloadService().downloadAndTrack(
      task.resourceId, task.url, task.fileName,
      title: task.title, subject: task.subject, grade: task.grade,
      type: task.type, mtime: task.mtime,
    );
    if (path != null) {
      if (task.title.isNotEmpty) {
        NotificationService().showDownloadComplete(task.title);
      }
      ActivityTracker().logKeyAction('download', resourceId: task.resourceId, metadata: task.title);
      _queue.removeAt(0);
      _finishTask();
      if (_queue.isNotEmpty) _processNext();
    } else if (task.retries > 0) {
      // Decrement retries and re-attempt with exponential backoff so transient
      // network or server issues have time to resolve.
      task.retries--;
      debugPrint('DownloadQueue: retrying ${task.resourceId} (${task.retries} attempts left)');
      final retryCount = 5 - task.retries; // 0-indexed attempt number
      final delay = Duration(seconds: 3 * (1 << retryCount)); // 3s, 6s, 12s, 24s, 48s
      await Future.delayed(delay);
      _processNext();
    } else {
      if (task.title.isNotEmpty) {
        NotificationService().showDownloadFailed(task.title);
      }
      _queue.removeAt(0);
      _finishTask();
      if (_queue.isNotEmpty) _processNext();
    }
  }
}
