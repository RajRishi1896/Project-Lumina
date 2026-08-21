import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../network/api_client.dart';
import '../storage/db_helper.dart';
import '../../shared/services/connectivity_service.dart';

/// Tracks study sessions and user actions, persists them locally, and
/// auto-syncs to the hub via [ApiClient].
class ActivityTracker {
  static final ActivityTracker _instance = ActivityTracker._internal();
  factory ActivityTracker() => _instance;
  ActivityTracker._internal();

  static const String _localEventsKey = 'local_events';
  static const String _activeStudySessionKey = 'active_study_session';
  static const String _cachedAnalyticsKey = 'cached_analytics';
  static const int _maxLocalEvents = 500;

  DateTime? _studyStartTime;
  Timer? _autoSyncTimer;

  /// Start the periodic auto-sync timer. Syncs every 60 seconds.
  void startAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 60), (_) => sync());
  }

  /// Record the start of a focused study session.
  Future<void> startStudySession({String? subject}) async {
    _studyStartTime = ApiClient.correctedNow();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeStudySessionKey, jsonEncode({
      'start_time': _studyStartTime!.toIso8601String(),
      'subject': subject,
    }));
  }

  /// Record the end of a focused study session and log the duration.
  Future<void> endStudySession() async {
    if (_studyStartTime == null) return;
    final duration = ApiClient.correctedNow().difference(_studyStartTime!);
    final prefs = await SharedPreferences.getInstance();
    final activeRaw = prefs.getString(_activeStudySessionKey);
    String? subject;
    if (activeRaw != null) {
      try {
        final activeData = jsonDecode(activeRaw);
        subject = activeData['subject'] as String?;
      } catch (_) { } }
    _studyStartTime = null;
    await prefs.remove(_activeStudySessionKey);
    final meta = <String, dynamic>{'duration_seconds': duration.inSeconds};
    if (subject != null && subject.isNotEmpty) {
      meta['subject'] = subject;
    }
    await _storeLocal(prefs, {
      'action': 'study_session',
      'resource_id': null,
      'metadata': jsonEncode(meta),
      'timestamp': ApiClient.correctedNow().toIso8601String(),
    });
    if (subject != null && subject.isNotEmpty && duration.inSeconds >= 30) {
      try {
        final db = await DBHelper().database;
        await db.insert('activity', {
          'resource_id': '',
          'date': ApiClient.correctedNow().toIso8601String().substring(0, 10),
          'subject': subject,
          'seconds': duration.inSeconds,
        });
      } catch (_) {}
    }
    await sync();
  }

  /// Logs a general user action to local storage for later sync.
  Future<void> logAction(String action, {String? resourceId, String? metadata}) async {
    final prefs = await SharedPreferences.getInstance();
    await _storeLocal(prefs, {
      'action': action,
      'resource_id': resourceId,
      'metadata': metadata,
      'timestamp': ApiClient.correctedNow().toIso8601String(),
    });
  }

  Future<void> _storeLocal(SharedPreferences prefs, Map<String, dynamic> event) async {
    final list = _decodeLocalEvents(prefs.getString(_localEventsKey));
    list.add(event);
    while (list.length > _maxLocalEvents) { list.removeAt(0); }
    await prefs.setString(_localEventsKey, jsonEncode(list));
  }

  List<Map<String, dynamic>> _decodeLocalEvents(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Get the recorded activity history for the current session.
  Future<List<Map<String, dynamic>>> getActivityHistory({int limit = 25}) async {
    final prefs = await SharedPreferences.getInstance();
    final list = _decodeLocalEvents(prefs.getString(_localEventsKey));
    if (list.isEmpty) return [];
    final all = list;
    all.sort((a, b) => (b['timestamp'] as String).compareTo(a['timestamp'] as String));
    final end = limit > all.length ? all.length : limit;
    return all.sublist(0, end);
  }

  /// Get analytics data including study time and streak info.
  Future<Map<String, dynamic>> getAnalytics() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cachedAnalyticsKey);
    if (cached != null) {
      try {
        final decoded = jsonDecode(cached);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) { } }

    // Cache empty, fetch from server (e.g. after data clear)
    try {
      final response = await ApiClient.get('/student/analytics');
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        await prefs.setString(_cachedAnalyticsKey, jsonEncode(response.data));
        return response.data;
      }
    } catch (_) { }

    return {
      'study_minutes_this_week': 0,
      'streak_days': 0,
      'resources_saved': 0,
    };
  }

  bool _inFlight = false;

  /// Force an immediate sync of pending activity data to the hub.
  Future<void> sync() async {
    if (!ConnectivityService().isOnline) return;
    if (_inFlight) return;
    _inFlight = true;
    try {
      await _sync();
    } finally {
      _inFlight = false;
    }
  }

  static String _eventKey(Map<String, dynamic> event) =>
      '${event['timestamp']}|${event['action']}|${event['resource_id']}|${event['metadata']}';

  Future<void> _sync() async {
    final prefs = await SharedPreferences.getInstance();
    final original = _decodeLocalEvents(prefs.getString(_localEventsKey));
    if (original.isEmpty) return;
    final list = [...original];

    final cutoff = ApiClient.correctedNow().subtract(const Duration(days: 7));
    final before = list.length;
    list.removeWhere((e) {
      final ts = DateTime.tryParse(e['timestamp'] as String? ?? '');
      return ts != null && ts.isBefore(cutoff);
    });
    final pruned = before - list.length;
    if (pruned > 0) {
      debugPrint('ActivityTracker: pruned $pruned old events');
    }

    // Compute total study seconds for the last 7 days
    int totalSeconds = 0;
    for (final event in list) {
      if (event['action'] == 'study_session') {
        final meta = event['metadata'] as String?;
        if (meta != null) {
          try {
            final decoded = jsonDecode(meta);
            totalSeconds += (decoded['duration_seconds'] as num?)?.toInt() ?? 0;
          } catch (_) { } }
      }
    }

    // Compute streak: consecutive days with activity going back from today
    final activeDates = <String>{};
    for (final event in list) {
      final ts = DateTime.tryParse(event['timestamp'] as String? ?? '');
      if (ts != null) activeDates.add(ts.toIso8601String().split('T')[0]);
    }
    int streak = 0;
    final today = ApiClient.correctedNow();
    for (int i = 0; i < 365; i++) {
      final d = today.subtract(Duration(days: i));
      final key = d.toIso8601String().split('T')[0];
      if (activeDates.contains(key)) {
        streak++;
      } else {
        break;
      }
    }

    try {
      await ApiClient.post('/student/sync-study-time', data: {
        'total_seconds': totalSeconds,
        'streak_days': streak,
      });
    } catch (_) {
      return;
    }

    // Compute and sync per-subject minutes
    final subjectMinutes = <String, int>{};
    for (final event in list) {
      if (event['action'] == 'study_session') {
        final meta = event['metadata'] as String?;
        if (meta != null) {
          try {
            final decoded = jsonDecode(meta);
            final subj = decoded['subject'] as String?;
            final secs = (decoded['duration_seconds'] as num?)?.toInt() ?? 0;
            if (subj != null && subj.isNotEmpty && secs > 0) {
              subjectMinutes[subj] = (subjectMinutes[subj] ?? 0) + secs;
            }
          } catch (_) { } }
      }
    }
    if (subjectMinutes.isNotEmpty) {
      final subjects = subjectMinutes.entries.map((e) => {
        'name': e.key,
        'minutes': (e.value / 60).round().clamp(0, 10080),
      }).toList();
      try {
        await ApiClient.post('/student/sync-subject-time', data: {'subjects': subjects});
      } catch (_) { } }

    /// Save pruned list, merging any events appended while this sync was in
    /// flight so concurrent logAction calls are not silently lost.
    final current = _decodeLocalEvents(prefs.getString(_localEventsKey));
    final known = original.map(_eventKey).toSet();
    for (final event in current) {
      if (!known.contains(_eventKey(event))) {
        list.add(event);
      }
    }
    while (list.length > _maxLocalEvents) { list.removeAt(0); }
    await prefs.setString(_localEventsKey, jsonEncode(list));
    try {
      final response = await ApiClient.get('/student/analytics');
      if (response.statusCode == 200) {
        await prefs.setString(_cachedAnalyticsKey, jsonEncode(response.data));
      }
    } catch (_) { } }
}
