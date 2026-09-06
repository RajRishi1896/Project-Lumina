import 'package:shared_preferences/shared_preferences.dart';
import '../../features/auth/data/auth_service.dart';

/// Prefixes SharedPreferences keys with the current user ID so each
/// profile gets its own namespace. Falls back to unprefixed keys
/// when no user is logged in (e.g., during initial setup).
class ProfileScopedPrefs {
  static Future<String> _prefix() async {
    final userId = await AuthService().getUniqueUserId();
    return userId != null ? '${userId}_' : '';
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
}
