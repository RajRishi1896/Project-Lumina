import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/network/api_client.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final _secureStorage = const FlutterSecureStorage();
  
  static const String _userIdKey = 'lumina_unique_user_id';
  static const String _usernameKey = 'lumina_username';
  static const String _usersListKey = 'lumina_users_list_secure';
  static const String _sessionTokenKey = 'session_token';

  // --- Demo Mode Configuration ---
  static const bool isDemoMode = false;
  static const String demoUserId = 'LUMINA_01-TESTDEMO';
  static const String demoUsername = 'test';

  static bool _demoRoleIsAdmin = true;

  static bool isAdmin() => isDemoMode ? _demoRoleIsAdmin : false;
  static bool isDemoAdmin() => _demoRoleIsAdmin;
  static void setDemoAdminRole(bool value) { _demoRoleIsAdmin = value; }

  String _hashPassword(String password) => sha256.convert(utf8.encode(password)).toString();

  Future<String?> getUniqueUserId() async {
    if (isDemoMode) return demoUserId;
    return _secureStorage.read(key: _userIdKey);
  }

  Future<String?> getLoggedUsername() async {
    if (isDemoMode) return demoUsername;
    return _secureStorage.read(key: _usernameKey);
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
      if (response.data == null || response.data is! Map) return false;
      final Map data = response.data;
      final String hubGeneratedId = data['id']?.toString() ?? '';
      final String? token = data['token']?.toString();
      
      List<Map<String, dynamic>> users = await _getUsers();
      if (users.any((u) => u['username'] == username)) return false;
      
      final newUser = {
        'username': username,
        'password': _hashPassword(password),
        'userId': hubGeneratedId,
      };
      
      users.add(newUser);
      await _secureStorage.write(key: _usersListKey, value: jsonEncode(users));
      
      await _secureStorage.write(key: _userIdKey, value: hubGeneratedId);
      await _secureStorage.write(key: _usernameKey, value: username);

      if (token != null) {
        await _secureStorage.write(key: _sessionTokenKey, value: token);
        ApiClient.setAuth(token);
      }
      
      return true;
    } catch (e) {
      return false;
    }
  }

  /// NEW: Hub-Verified Login for New Devices
  Future<String?> login({
    required String username,
    required String password,
  }) async {
    try {
      final rawInput = _hashPassword(password);

      // 1. Try Local First
      List<Map<String, dynamic>> users = await _getUsers();
      final localUser = users.firstWhere(
        (u) => u['username'] == username && u['password'] == rawInput,
        orElse: () => {},
      );

      if (localUser.isNotEmpty) {
        _saveSession(localUser['userId'], username);
        try {
          final loginResp = await ApiClient.post('/student/token', data: {'username': username, 'password': password});
          final Map respData = loginResp.data;
          final String token = respData['token']?.toString() ?? '';
          final String scholarId = respData['scholar_id']?.toString() ?? '';
          final bool resetReq = respData['reset_required'] == true;
          if (token.isNotEmpty) {
            await _secureStorage.write(key: _sessionTokenKey, value: token);
            await _secureStorage.write(key: _userIdKey, value: scholarId);
            ApiClient.setAuth(token);
          }
          return resetReq ? 'reset_required' : 'ok';
        } catch (_) {}
        return 'ok';
      }

      // On new device, try to get student info from server
      try {
        final loginResp = await ApiClient.post('/student/token', data: {
          'username': username,
          'password': password,
        });
        if (loginResp.statusCode == 200 && loginResp.data is Map) {
          final respData = loginResp.data as Map;
          final String? token = respData['token']?.toString();
          final String? scholarId = respData['scholar_id']?.toString();
          final String? name = respData['name']?.toString();
          final bool resetReq = respData['reset_required'] == true;
          if (token != null && scholarId != null) {
            await _secureStorage.write(key: _sessionTokenKey, value: token);
            await _secureStorage.write(key: _userIdKey, value: scholarId);
            if (name != null) await _secureStorage.write(key: _usernameKey, value: name);
            ApiClient.setAuth(token);
            return resetReq ? 'reset_required' : 'ok';
          }
        }
      } catch (_) {
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> _saveSession(String id, String username) async {
    await _secureStorage.write(key: _userIdKey, value: id);
    await _secureStorage.write(key: _usernameKey, value: username);
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
    try {
      await ApiClient.post('/logout');
    } catch (_) {}
    await _secureStorage.deleteAll();
  }

  Future<int> getApkSize() async {
    return 65 * 1024 * 1024;
  }
}
