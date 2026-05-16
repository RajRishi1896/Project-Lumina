import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final _secureStorage = const FlutterSecureStorage();
  
  static const String _userIdKey = 'lumina_unique_user_id';
  static const String _usernameKey = 'lumina_username';
  static const String _usersListKey = 'lumina_users_list_secure';

  /// Hashes the password using SHA-256 for secure storage
  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<String?> getUniqueUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userIdKey);
  }

  Future<String?> getLoggedUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_usernameKey);
  }

  /// Registration: Creates a new user profile with hashed password
  Future<bool> register({
    required String username,
    required String password,
  }) async {
    try {
      await Future.delayed(const Duration(seconds: 1));
      
      List<Map<String, dynamic>> users = await _getUsers();
      
      if (users.any((u) => u['username'] == username)) {
        return false; // User already exists
      }
      
      final random = Random();
      final id = 'LUM-US-${random.nextInt(9999).toString().padLeft(4, '0')}-${random.nextInt(9999).toString().padLeft(4, '0')}';
      
      final newUser = {
        'username': username,
        'password': _hashPassword(password), // Store hashed password
        'userId': id,
      };
      
      users.add(newUser);
      await _secureStorage.write(key: _usersListKey, value: jsonEncode(users));
      
      // Auto-login
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userIdKey, id);
      await prefs.setString(_usernameKey, username);
      
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Login: Authenticates against existing profiles with hashed password check
  Future<bool> login({
    required String username,
    required String password,
  }) async {
    try {
      await Future.delayed(const Duration(seconds: 1));
      
      List<Map<String, dynamic>> users = await _getUsers();
      final hashedInput = _hashPassword(password);
      
      final user = users.firstWhere(
        (u) => u['username'] == username && u['password'] == hashedInput,
        orElse: () => {},
      );
      
      if (user.isEmpty) {
        return false;
      }
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userIdKey, user['userId']);
      await prefs.setString(_usernameKey, username);
      
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> _getUsers() async {
    final String? usersJson = await _secureStorage.read(key: _usersListKey);
    if (usersJson == null) return [];
    try {
      return List<Map<String, dynamic>>.from(jsonDecode(usersJson));
    } catch (e) {
      return [];
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userIdKey);
    await prefs.remove(_usernameKey);
  }

  /// Calculates APK size (estimated for debug/demonstration)
  Future<int> getApkSize() async {
    try {
      // In a real environment, this would be the actual file size of the APK.
      return 65 * 1024 * 1024; // 65MB overhead
    } catch (e) {
      return 0;
    }
  }
}
