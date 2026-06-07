import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../network/api_client.dart';
import '../../shared/services/connectivity_service.dart';

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

  void startAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 60), (_) => sync());
  }

  void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  Future<void> startStudySession({String? subject}) async {
    _studyStartTime = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeStudySessionKey, jsonEncode({
      'start_time': _studyStartTime!.toIso8601String(),
      'subject': subject,
    }));
  }

  Future<void> endStudySession() async {
    if (_studyStartTime == null) return;
    final duration = DateTime.now().difference(_studyStartTime!);
    final prefs = await SharedPreferences.getInstance();
    final activeRaw = prefs.getString(_activeStudySessionKey);
    String? subject;
    if (activeRaw != null) {
      try {
        final activeData = jsonDecode(activeRaw);
        subject = activeData['subject'] as String?;
      } catch (_) {}
    }
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

  Future<void> logAction(String action, {String? resourceId, String? metadata}) async {
    final prefs = await SharedPreferences.getInstance();
    await _storeLocal(prefs, {
      'action': action,
      'resource_id': resourceId,
      'metadata': metadata,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<void> logKeyAction(String action, {String? resourceId, String? metadata}) async {
    final prefs = await SharedPreferences.getInstance();
    await _storeLocal(prefs, {
      'action': action,
      'resource_id': resourceId,
      'metadata': metadata,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _storeLocal(SharedPreferences prefs, Map<String, dynamic> event) async {
    final raw = prefs.getString(_localEventsKey);
    final list = raw != null ? (jsonDecode(raw) as List).cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
    list.add(event);
    if (list.length > _maxLocalEvents) list.removeAt(0);
    await prefs.setString(_localEventsKey, jsonEncode(list));
  }

  Future<List<Map<String, dynamic>>> getActivityHistory({int limit = 25, int offset = 0}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_localEventsKey);
    if (raw == null) return [];
    final all = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    all.sort((a, b) => (b['timestamp'] as String).compareTo(a['timestamp'] as String));
    final end = offset + limit;
    if (offset >= all.length) return [];
    return all.sublist(offset, end > all.length ? all.length : end);
  }

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
      'study_minutes_this_week': 0,
      'streak_days': 0,
      'resources_saved': 0,
    };
  }

  Future<void> sync() async {
    if (!ConnectivityService().isOnline) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_localEventsKey);
    if (raw == null) return;
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return;

    // Prune events older than 7 days
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
          } catch (_) {}
        }
      }
    }

    // Compute streak: consecutive days with activity going back from today
    final activeDates = <String>{};
    for (final event in list) {
      final ts = DateTime.tryParse(event['timestamp'] as String? ?? '');
      if (ts != null) activeDates.add(ts.toIso8601String().split('T')[0]);
    }
    int streak = 0;
    final today = DateTime.now();
    for (int i = 0; i < 365; i++) {
      final d = today.subtract(Duration(days: i));
      final key = d.toIso8601String().split('T')[0];
      if (activeDates.contains(key)) {
        streak++;
      } else {
        break;
      }
    }

    // Sync to server
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
          } catch (_) {}
        }
      }
    }
    if (subjectMinutes.isNotEmpty) {
      final subjects = subjectMinutes.entries.map((e) => {
        'name': e.key,
        'minutes': (e.value / 60).round().clamp(0, 10080),
      }).toList();
      try {
        await ApiClient.post('/student/sync-subject-time', data: {'subjects': subjects});
      } catch (_) {}
    }

    // Save pruned list and refresh cached analytics
    await prefs.setString(_localEventsKey, jsonEncode(list));
    try {
      final response = await ApiClient.get('/student/analytics');
      if (response.statusCode == 200) {
        await prefs.setString(_cachedAnalyticsKey, jsonEncode(response.data));
      }
    } catch (_) {}
  }
}
