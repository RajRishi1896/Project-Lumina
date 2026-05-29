import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/network/api_client.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final _secureStorage = const FlutterSecureStorage();
  
  static const String _userIdKey = 'lumina_unique_user_id';
  static const String _usernameKey = 'lumina_username';
  static const String _usersListKey = 'lumina_users_list_secure';

  // --- Demo Mode Configuration ---
  static const bool isDemoMode = true; // Set to true to skip login and use test profile
  static const String demoUserId = 'LUMINA_01-TESTDEMO';
  static const String demoUsername = 'test';

  static bool isAdmin() => isDemoMode;

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<String?> getUniqueUserId() async {
    if (isDemoMode) return demoUserId;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userIdKey);
  }

  Future<String?> getLoggedUsername() async {
    if (isDemoMode) return demoUsername;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_usernameKey);
  }

  Future<bool> register({
    required String username,
    required String password,
  }) async {
    try {
      final response = await ApiClient.post('/register', data: {
        'name': username,
      });

      if (response.statusCode != 200) return false;
      final String hubGeneratedId = response.data['id'];
      
      List<Map<String, dynamic>> users = await _getUsers();
      if (users.any((u) => u['username'] == username)) return false;
      
      final newUser = {
        'username': username,
        'password': _hashPassword(password),
        'userId': hubGeneratedId,
      };
      
      users.add(newUser);
      await _secureStorage.write(key: _usersListKey, value: jsonEncode(users));
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userIdKey, hubGeneratedId);
      await prefs.setString(_usernameKey, username);
      
      return true;
    } catch (e) {
      return false;
    }
  }

  /// NEW: Hub-Verified Login for New Devices
  Future<bool> login({
    required String username,
    required String password,
  }) async {
    try {
      final hashedInput = _hashPassword(password);
      
      // 1. Try Local First
      List<Map<String, dynamic>> users = await _getUsers();
      final localUser = users.firstWhere(
        (u) => u['username'] == username && u['password'] == hashedInput,
        orElse: () => {},
      );
      
      if (localUser.isNotEmpty) {
        _saveSession(localUser['userId'], username);
        return true;
      }

      // 2. If not local, check the Hub (New Device Scenario)
      // Note: We search the scholar list on the Hub for a matching name
      final response = await ApiClient.get('/teacher/scholars');
      if (response.statusCode == 200) {
        final List<dynamic> hubScholars = response.data;
        final matchingScholar = hubScholars.firstWhere(
          (s) => s['name'] == username,
          orElse: () => null,
        );

        if (matchingScholar != null) {
          final String hubId = matchingScholar['id'];
          
          // Save to local secure storage for next time
          users.add({
            'username': username,
            'password': hashedInput,
            'userId': hubId,
          });
          await _secureStorage.write(key: _usersListKey, value: jsonEncode(users));
          
          _saveSession(hubId, username);
          return true;
        }
      }
      
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> _saveSession(String id, String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userIdKey, id);
    await prefs.setString(_usernameKey, username);
  }

  Future<List<Map<String, dynamic>>> _getUsers() async {
    try {
      final String? usersJson = await _secureStorage.read(key: _usersListKey);
      if (usersJson == null) return [];
      return List<Map<String, dynamic>>.from(jsonDecode(usersJson));
    } catch (e) { 
      // EDGE CASE: If Android Keystore is corrupted (e.g. user removed lock screen PIN),
      // read() throws an exception. We must wipe the corrupted storage to prevent a permanent crash loop.
      await _secureStorage.deleteAll();
      return []; 
    }
  }

  Future<void> logout() async {
    if (isDemoMode) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userIdKey);
    await prefs.remove(_usernameKey);
  }

  Future<int> getApkSize() async {
    return 65 * 1024 * 1024;
  }
}
