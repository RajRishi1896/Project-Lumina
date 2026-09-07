import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../network/api_client.dart';
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
  // ponytail: getInstance() is a singleton lookup; cache the future's result
  // so hot paths (logAction) skip an async hop per call.
  SharedPreferences? _prefs;

  Future<SharedPreferences> _getPrefs() async =>
      _prefs ??= await SharedPreferences.getInstance();

  /// Start the periodic auto-sync timer. Syncs every 60 seconds.
  void startAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 60), (_) => sync());
  }

  /// Clears in-memory study-session state.
  ///
  /// Called on logout/profile switch so a stale session's duration is never
  /// recorded under another student's profile.
  void resetSessionState() {
    _studyStartTime = null;
  }

  /// Handle app lifecycle changes. Ends study session when app goes to
  /// background or is inactive, so time spent in PiP or with screen off
  /// is accounted for.
  void onLifecycleChange(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (_studyStartTime != null) {
        unawaited(endStudySession());
      }
    }
  }

  /// Record the start of a focused study session.
  ///
  /// Flushes any active session first: overlapping viewers (PDF open under
  /// a mini-player video) must both earn their time, not lose the first.
  Future<void> startStudySession({String? subject}) async {
    await endStudySession();
    final subj = subject?.trim();
    _studyStartTime = DateTime.now();
    final prefs = await _getPrefs();
    await prefs.setString(_activeStudySessionKey, jsonEncode({
      'start_time': _studyStartTime!.toIso8601String(),
      'subject': (subj != null && subj.isNotEmpty) ? subj : null,
    }));
  }

  /// Record the end of a focused study session and log the duration.
  Future<void> endStudySession() async {
    if (_studyStartTime == null) return;
    final duration = DateTime.now().difference(_studyStartTime!);
    final prefs = await _getPrefs();
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
      'timestamp': DateTime.now().toIso8601String(),
    });
    await sync();
  }

  /// Logs a general user action to local storage for later sync.
  Future<void> logAction(String action, {String? resourceId, String? metadata}) async {
    final prefs = await _getPrefs();
    await _storeLocal(prefs, {
      'action': action,
      'resource_id': resourceId,
      'metadata': metadata,
      'timestamp': DateTime.now().toIso8601String(),
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

  /// All buffered local events, oldest first.
  Future<List<Map<String, dynamic>>> getLocalEvents() async {
    final prefs = await _getPrefs();
    return _decodeLocalEvents(prefs.getString(_localEventsKey));
  }

  /// Study seconds logged locally today (device midnight boundary).
  ///
  /// The server only tracks weekly totals, so "today" is computed from
  /// local study_session events. Returns 0 when there are none.
  Future<int> studySecondsToday() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    var total = 0;
    for (final event in await getLocalEvents()) {
      if (event['action'] != 'study_session') continue;
      final ts = DateTime.tryParse(event['timestamp'] as String? ?? '');
      if (ts == null || ts.isBefore(startOfDay)) continue;
      final meta = event['metadata'] as String?;
      if (meta == null) continue;
      try {
        final decoded = jsonDecode(meta);
        total += (decoded['duration_seconds'] as num?)?.toInt() ?? 0;
      } catch (_) {}
    }
    return total;
  }

  /// Get the recorded activity history for the current session.
  Future<List<Map<String, dynamic>>> getActivityHistory({int limit = 25}) async {
    final prefs = await _getPrefs();
    final list = _decodeLocalEvents(prefs.getString(_localEventsKey));
    if (list.isEmpty) return [];
    final all = list;
    all.sort((a, b) => (b['timestamp'] as String? ?? '').compareTo(a['timestamp'] as String? ?? ''));
    final end = limit > all.length ? all.length : limit;
    return all.sublist(0, end);
  }

  /// Get analytics data including study time and streak info.
  ///
  /// Fetches fresh analytics from the hub when online and caches the result
  /// on success; the cached copy is only used as an offline/failure fallback.
  Future<Map<String, dynamic>> getAnalytics() async {
    final prefs = await _getPrefs();
    if (ConnectivityService().isOnline) {
      try {
        final response = await ApiClient.get('/student/analytics');
        if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
          await prefs.setString(_cachedAnalyticsKey, jsonEncode(response.data));
          return response.data;
        }
      } catch (_) { }
    }

    // Offline (or fetch failed): fall back to the cached copy.
    final cached = prefs.getString(_cachedAnalyticsKey);
    if (cached != null) {
      try {
        final decoded = jsonDecode(cached);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) { }
    }

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
    // Snapshot before reading events: if the profile switches mid-sync,
    // everything we read/post/write belongs to the previous student.
    final gen = ApiClient.sessionGeneration;
    final prefs = await _getPrefs();
    final original = _decodeLocalEvents(prefs.getString(_localEventsKey));
    if (original.isEmpty) return;
    final list = [...original];

    final cutoff = DateTime.now().subtract(const Duration(days: 7));
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

    // Compute streak: consecutive days with activity ending today. Built
    // from the FULL event history (pre-prune), otherwise the 7-day cutoff
    // above would silently cap the streak at 7 despite the 365-day loop.
    final activeDates = <String>{};
    for (final event in original) {
      final ts = DateTime.tryParse(event['timestamp'] as String? ?? '');
      if (ts != null) activeDates.add(ts.toIso8601String().split('T')[0]);
    }
    int streak = 0;
    final today = DateTime.now();
    final todayKey = today.toIso8601String().split('T')[0];
    // If the student has not studied yet today, count from yesterday
    // instead of breaking on today: posting streak=0 every morning would
    // zero the stored streak before the first session of the day.
    final int start = activeDates.contains(todayKey) ? 0 : 1;
    for (int i = start; i < start + 365; i++) {
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
    // Profile switched mid-sync: everything from here on belongs to
    // another student. Abort silently; nothing is written back.
    if (ApiClient.sessionGeneration != gen) return;

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
        'seconds': e.value.clamp(0, 604800),
      }).toList();
      try {
        await ApiClient.post('/student/sync-subject-time', data: {'subjects': subjects});
      } catch (_) { } }

    /// Save pruned list, merging any events appended while this sync was in
    /// flight so concurrent logAction calls are not silently lost.
    if (ApiClient.sessionGeneration != gen) return;
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
