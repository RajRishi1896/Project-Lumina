import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../network/api_client.dart';
import '../services/auth_service.dart';

class SyncService {
  final AuthService _authService = AuthService();
  static const String _queueKey = 'lumina_sync_queue';

  /// Logs a scholar's action. If offline, saves to a local queue.
  Future<void> logActivity(String action, String resourceId) async {
    final scholarId = await _authService.getUniqueUserId();
    if (scholarId == null) return;

    final activity = {
      'scholar_id': scholarId,
      'action': action,
      'resource_id': resourceId,
      'timestamp': DateTime.now().toIso8601String(),
    };

    try {
      // 1. First, sync the Hub's clock using the phone's accurate time
      await _syncTimeWithHub();

      // 2. Try to send activity
      final response = await ApiClient.post('/sync/activity', data: activity);
      if (response.statusCode != 200) {
        await _addToQueue(activity);
      } else {
        await processQueue();
      }
    } catch (e) {
      await _addToQueue(activity);
    }
  }

  /// Sends the current phone time to the Hub to fix "1970 clock drift"
  Future<void> _syncTimeWithHub() async {
    try {
      final now = DateTime.now();
      
      // SANITY CHECK: If the phone's battery died and reset to 2010, do NOT sync.
      if (now.year < 2025) {
        debugPrint("Time Sync Blocked: Phone clock is inaccurate (${now.year}).");
        return;
      }
      
      final isoString = now.toIso8601String();
      await ApiClient.post('/system/sync-time', data: {
        'current_time': isoString,
      });
    } catch (e) {
      debugPrint('Time sync failed: $e');
    }
  }

  Future<void> processQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final String? queueJson = prefs.getString(_queueKey);
    if (queueJson == null) return;

    List<dynamic> queue = jsonDecode(queueJson);
    if (queue.isEmpty) return;

    List<dynamic> failedItems = [];
    for (var item in queue) {
      try {
        final res = await ApiClient.post('/sync/activity', data: item);
        if (res.statusCode != 200) failedItems.add(item);
      } catch (e) {
        failedItems.add(item);
      }
    }
    await prefs.setString(_queueKey, jsonEncode(failedItems));
  }

  Future<void> _addToQueue(Map<String, dynamic> item) async {
    final prefs = await SharedPreferences.getInstance();
    final String? queueJson = prefs.getString(_queueKey);
    List<dynamic> queue = queueJson != null ? jsonDecode(queueJson) : [];
    
    // EDGE CASE: If offline for months, the queue could grow infinitely and crash SharedPreferences
    if (queue.length >= 1000) {
      queue.removeAt(0); // Drop the oldest item
    }
    
    queue.add(item);
    await prefs.setString(_queueKey, jsonEncode(queue));
  }

  Future<void> syncDownloadHistory(List<String> resourceIds) async {
    try {
      final scholarId = await _authService.getUniqueUserId();
      if (scholarId == null) return;
      await ApiClient.post('/sync/downloads', data: {
        'scholar_id': scholarId,
        'resource_ids': resourceIds,
      });
    } catch (e) {}
  }

  Future<Map<String, dynamic>?> restoreProfile() async {
    try {
      final scholarId = await _authService.getUniqueUserId();
      if (scholarId == null) return null;
      final response = await ApiClient.get('/sync/restore/$scholarId');
      if (response.statusCode == 200) return response.data;
      return null;
    } catch (e) { return null; }
  }
}
