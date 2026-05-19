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
        'password': password,
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
      await prefs.setBool('lumina_is_teacher', false);
      await prefs.setInt('lumina_student_reset_required', 0);
      
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Hub-Verified Login with teacher/student separation
  Future<bool> login({
    required String username,
    required String password,
  }) async {
    try {
      // First, check if this is a Teacher login by verifying with Hub /token endpoint
      try {
        final tokenResp = await ApiClient.post('/token', data: {
          'username': username,
          'password': password,
        });
        if (tokenResp.statusCode == 200 && tokenResp.data['is_teacher'] == true) {
          final String hubId = tokenResp.data['scholar_id'] ?? 'LUMINA_01-TEACHER';
          final String name = tokenResp.data['name'] ?? username;
          final String dept = tokenResp.data['department'] ?? 'General';
          final int resetReq = tokenResp.data['reset_required'] ?? 0;

          // Save session as teacher
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_userIdKey, hubId);
          await prefs.setString(_usernameKey, username);
          await prefs.setBool('lumina_is_teacher', true);
          await prefs.setString('lumina_teacher_name', name);
          await prefs.setString('lumina_teacher_dept', dept);
          await prefs.setInt('lumina_teacher_reset_required', resetReq);

          // Also save to secure storage
          List<Map<String, dynamic>> users = await _getUsers();
          users.removeWhere((u) => u['username'] == username);
          users.add({
            'username': username,
            'password': _hashPassword(password),
            'userId': hubId,
            'isTeacher': true,
          });
          await _secureStorage.write(key: _usersListKey, value: jsonEncode(users));

          return true;
        }
      } catch (_) {
        // Not a teacher or invalid teacher creds, fall through to student check
      }

      // Second, verify student login on the Hub
      try {
        final studentResp = await ApiClient.post('/student/token', data: {
          'username': username,
          'password': password,
        });

        if (studentResp.statusCode == 200 && studentResp.data['scholar_id'] != null) {
          final String hubId = studentResp.data['scholar_id'];
          final int resetReq = studentResp.data['reset_required'] ?? 0;

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_userIdKey, hubId);
          await prefs.setString(_usernameKey, username);
          await prefs.setBool('lumina_is_teacher', false);
          await prefs.setInt('lumina_student_reset_required', resetReq);

          // Update local secure storage
          List<Map<String, dynamic>> users = await _getUsers();
          users.removeWhere((u) => u['username'] == username);
          users.add({
            'username': username,
            'password': _hashPassword(password),
            'userId': hubId,
            'isTeacher': false,
          });
          await _secureStorage.write(key: _usersListKey, value: jsonEncode(users));

          return true;
        }
      } catch (_) {
        // Student login failed
      }

      final hashedInput = _hashPassword(password);
      
      // 1. Try Local First
      List<Map<String, dynamic>> users = await _getUsers();
      final localUser = users.firstWhere(
        (u) => u['username'] == username && u['password'] == hashedInput,
        orElse: () => {},
      );
      
      if (localUser.isNotEmpty) {
        final bool isT = localUser['isTeacher'] == true;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_userIdKey, localUser['userId']);
        await prefs.setString(_usernameKey, username);
        await prefs.setBool('lumina_is_teacher', isT);
        return true;
      }
      
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> changeStudentPassword(String newPassword) async {
    try {
      final String? scholarId = await getUniqueUserId();
      final String? username = await getLoggedUsername();
      if (scholarId == null || username == null) return false;

      final response = await ApiClient.post('/student/change-password', data: {
        'scholar_id': scholarId,
        'new_password': newPassword,
      });

      if (response.statusCode == 200) {
        // Update local secure storage hash
        List<Map<String, dynamic>> users = await _getUsers();
        users.removeWhere((u) => u['username'] == username);
        users.add({
          'username': username,
          'password': _hashPassword(newPassword),
          'userId': scholarId,
          'isTeacher': false,
        });
        await _secureStorage.write(key: _usersListKey, value: jsonEncode(users));

        // Clear local reset flag
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('lumina_student_reset_required', 0);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> isTeacher() async {
    if (isDemoMode) return true;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('lumina_is_teacher') ?? false;
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
      await _secureStorage.deleteAll();
      return []; 
    }
  }

  Future<void> logout() async {
    if (isDemoMode) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userIdKey);
    await prefs.remove(_usernameKey);
    await prefs.remove('lumina_student_reset_required');
    await prefs.remove('lumina_teacher_reset_required');
  }

  Future<int> getApkSize() async {
    return 65 * 1024 * 1024;
  }
}
