import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../network/api_client.dart';
import '../../features/auth/data/auth_service.dart';

/// Singleton that tracks user activity (study sessions, resource views, etc.)
/// and syncs them to the server. Queues events in SharedPreferences when offline
/// and flushes them on connectivity restoration.
class ActivityTracker {
  static final ActivityTracker _instance = ActivityTracker._internal();
  factory ActivityTracker() => _instance;
  ActivityTracker._internal();

  static const String _activityQueueKey = 'activity_queue';
  static const String _activeStudySessionKey = 'active_study_session';
  static const String _cachedAnalyticsKey = 'cached_analytics';
  static const String _cachedHistoryKey = 'cached_activity_history';

  DateTime? _studyStartTime;
  Timer? _autoSyncTimer;
  int _lastSyncMs = 0;

  /// Starts a periodic timer that syncs queued activity to the server every 60 seconds.
  void startAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 60), (_) => sync());
  }

  /// Cancels the periodic auto-sync timer.
  void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  /// Begins a new study session by recording the current time in SharedPreferences.
  Future<void> startStudySession() async {
    _studyStartTime = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeStudySessionKey, jsonEncode({
      'start_time': _studyStartTime!.toIso8601String(),
    }));
  }

  /// Ends the current study session, queues the duration, and immediately syncs.
  Future<void> endStudySession() async {
    if (_studyStartTime == null) return;
    final duration = DateTime.now().difference(_studyStartTime!);
    _studyStartTime = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeStudySessionKey);
    await _enqueue(prefs, {
      'action': 'study_session',
      'resource_id': null,
      'metadata': jsonEncode({'duration_seconds': duration.inSeconds}),
      'timestamp': DateTime.now().toIso8601String(),
    });
    await _trySync(prefs);
  }

  /// Logs an [action] (e.g. "resource_view") with optional [resourceId] and [metadata].
  /// Queues the event locally and syncs if at least 15 seconds have elapsed since the last sync.
  Future<void> logAction(String action, {String? resourceId, String? metadata}) async {
    final prefs = await SharedPreferences.getInstance();
    await _enqueue(prefs, {
      'action': action,
      'resource_id': resourceId,
      'metadata': metadata,
      'timestamp': DateTime.now().toIso8601String(),
    });
    await _trySync(prefs);
  }

  Future<void> _enqueue(SharedPreferences prefs, Map<String, dynamic> event) async {
    final queue = _decodeQueue(prefs.getString(_activityQueueKey));
    queue.add(event);
    await prefs.setString(_activityQueueKey, jsonEncode(queue));
  }

  List<Map<String, dynamic>> _decodeQueue(String? raw) {
    if (raw == null) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded.cast<Map<String, dynamic>>();
  }

  /// Sync only if at least 15 seconds have passed since last sync.
  Future<void> _trySync(SharedPreferences prefs) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSyncMs < 15000) return;
    _lastSyncMs = now;
    await _doSync(prefs);
  }

  /// A paginated list of recent activity events fetched from the server or from cache.
  Future<List<Map<String, dynamic>>> getActivityHistory({int limit = 25, int offset = 0}) async {
    final prefs = await SharedPreferences.getInstance();
    final scholarId = await AuthService().getUniqueUserId();
    if (scholarId != null) {
      try {
        final response = await ApiClient.get('/student/activity', queryParameters: {
          'limit': limit.toString(),
          'offset': offset.toString(),
        });
        if (response.statusCode == 200 && response.data is List) {
          final data = (response.data as List).map((e) => Map<String, dynamic>.from(e)).toList();
          await prefs.setString(_cachedHistoryKey, jsonEncode(data));
          return data;
        }
      } catch (_) {}
    }
    final cached = prefs.getString(_cachedHistoryKey);
    if (cached != null) {
      final decoded = jsonDecode(cached);
      if (decoded is List) return decoded.cast<Map<String, dynamic>>();
    }
    return [];
  }

  /// The cached analytics summary (study minutes, streak, resources saved, etc.).
  /// Returns default zero values if no cached data is available.
  Future<Map<String, dynamic>> getAnalytics() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cachedAnalyticsKey);
    if (cached != null) {
      try {
        final decoded = jsonDecode(cached);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    return {
      'study_minutes_today': 0,
      'study_minutes_this_week': 0,
      'study_minutes_this_month': 0,
      'streak_days': 0,
      'resources_saved': 0,
      'subjects': [],
    };
  }

  /// Forces an immediate sync of all queued activity events to the server.
  Future<void> sync() async {
    final prefs = await SharedPreferences.getInstance();
    await _doSync(prefs);
  }

  Future<void> _doSync(SharedPreferences prefs) async {
    final raw = prefs.getString(_activityQueueKey);
    if (raw == null) return;
    final queue = _decodeQueue(raw);
    if (queue.isEmpty) return;

    final List<Map<String, dynamic>> failed = [];
    for (final event in queue) {
      try {
        final action = event['action'] as String;
        if (action == 'study_session') {
          final startResp = await ApiClient.post('/student/study/start');
          final sessionId = (startResp.data is Map) ? (startResp.data as Map)['session_id'] : null;
          final metadata = event['metadata'] != null
              ? jsonDecode(event['metadata'] as String) as Map<String, dynamic>
              : <String, dynamic>{};
          await ApiClient.post('/student/study/end', data: {
            'session_id': sessionId,
            'duration_seconds': metadata['duration_seconds'],
          });
        } else {
          await ApiClient.post('/student/activity', data: {
            'action': action,
            'resource_id': event['resource_id'],
            'metadata': event['metadata'],
          });
        }
      } catch (_) {
        failed.add(event);
      }
    }
    await prefs.setString(_activityQueueKey, jsonEncode(failed));

    try {
      final response = await ApiClient.get('/student/analytics');
      if (response.statusCode == 200) {
        await prefs.setString(_cachedAnalyticsKey, jsonEncode(response.data));
      }
    } catch (_) {}
  }

  /// Logs a short-lived key action and triggers an immediate sync to the server.
  Future<void> logKeyAction(String action, {String? resourceId, String? metadata}) async {
    final prefs = await SharedPreferences.getInstance();
    await _enqueue(prefs, {
      'action': action,
      'resource_id': resourceId,
      'metadata': metadata,
      'timestamp': DateTime.now().toIso8601String(),
    });
    _lastSyncMs = 0;
    await _trySync(prefs);
  }
}
