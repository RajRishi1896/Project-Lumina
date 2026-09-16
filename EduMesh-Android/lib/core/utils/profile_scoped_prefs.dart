import 'package:shared_preferences/shared_preferences.dart';

/// Prefixes SharedPreferences keys with the current user ID so each
/// profile gets its own namespace. Falls back to unprefixed keys
/// when no user is logged in (e.g., during initial setup).
///
/// The user ID is read from SharedPreferences (not secure storage) to
/// avoid platform-channel hangs in the test runner.
class ProfileScopedPrefs {
  static const _userIdPrefKey = 'profile_scope_user_id';

  static Future<String> _prefix() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(_userIdPrefKey);
    return userId != null ? '${userId}_' : '';
  }

  /// Stores the user ID used for key prefixing. Call this after login
  /// so subsequent reads scope to the correct profile.
  static Future<void> setUserId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userIdPrefKey, userId);
  }

  /// Clears the scoped user ID. Call this on logout.
  static Future<void> clearUserId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userIdPrefKey);
  }

  static Future<bool> getBool(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('${await _prefix()}$key') ?? false;
  }

  static Future<void> setBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${await _prefix()}$key', value);
  }

  static Future<String?> getString(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('${await _prefix()}$key');
  }

  static Future<void> setString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${await _prefix()}$key', value);
  }

  static Future<int> getInt(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('${await _prefix()}$key') ?? 0;
  }

  static Future<void> setInt(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('${await _prefix()}$key', value);
  }

  static Future<List<String>> getStringList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('${await _prefix()}$key') ?? const [];
  }

  static Future<void> setStringList(String key, List<String> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('${await _prefix()}$key', value);
  }

  static Future<void> remove(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('${await _prefix()}$key');
  }
}
