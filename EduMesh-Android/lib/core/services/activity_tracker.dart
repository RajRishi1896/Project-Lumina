import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../network/api_client.dart';
import '../../features/auth/data/auth_service.dart';

class ActivityTracker {
  static final ActivityTracker _instance = ActivityTracker._internal();
  factory ActivityTracker() => _instance;
  ActivityTracker._internal();

  static const String _activityQueueKey = 'activity_queue';
  static const String _activeStudySessionKey = 'active_study_session';
  static const String _cachedAnalyticsKey = 'cached_analytics';

  DateTime? _studyStartTime;

  Future<void> startStudySession() async {
    _studyStartTime = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeStudySessionKey, jsonEncode({
      'start_time': _studyStartTime!.toIso8601String(),
    }));
  }

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
  }

  Future<void> logAction(String action, {String? resourceId, String? metadata}) async {
    final prefs = await SharedPreferences.getInstance();
    await _enqueue(prefs, {
      'action': action,
      'resource_id': resourceId,
      'metadata': metadata,
      'timestamp': DateTime.now().toIso8601String(),
    });
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

  static const String _cachedHistoryKey = 'cached_activity_history';

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
          final data = (response.data as List).cast<Map<String, dynamic>>();
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

  Future<Map<String, dynamic>> getAnalytics() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cachedAnalyticsKey);
    if (cached != null) {
      return jsonDecode(cached) as Map<String, dynamic>;
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

  Future<void> sync() async {
    final prefs = await SharedPreferences.getInstance();
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
}
