import 'package:shared_preferences/shared_preferences.dart';

/// Tracks the last 5 resources the user actually opened (PDF, video, quiz, etc.).
class RecentResources {
  static const _key = 'recent_resources_v1';
  static const _max = 5;

  /// Record a resource view. Call this when the user actually opens a resource
  /// (PDF viewer, video player, quiz player, kiwix view).
  static Future<void> record(String id, String title, String type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_key) ?? [];
      final entry = '$id|||$title|||$type';
      raw.removeWhere((e) => e.startsWith('$id|||'));
      raw.insert(0, entry);
      if (raw.length > _max) raw.removeRange(_max, raw.length);
      await prefs.setStringList(_key, raw);
    } catch (_) {}
  }

  /// Load the last 5 recently accessed resources.
  static Future<List<Map<String, String>>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_key) ?? [];
      return raw.map((e) {
        final parts = e.split('|||');
        return {
          'id': parts[0],
          'title': parts.length > 1 ? parts[1] : '',
          'type': parts.length > 2 ? parts[2] : '',
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
