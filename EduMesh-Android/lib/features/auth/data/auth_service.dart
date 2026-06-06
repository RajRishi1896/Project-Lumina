import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/network/api_client.dart';

/// A singleton service managing student authentication and secure credential storage.
///
/// Wraps [FlutterSecureStorage] to persist user id, username, session token,
/// grade, and a local user database. Performs hub-verified login with offline
/// fallback using a SHA-256 hashed local user list.
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final _secureStorage = const FlutterSecureStorage();
  
  static const String _userIdKey = 'lumina_unique_user_id';
  static const String _usernameKey = 'lumina_username';
  static const String _usersListKey = 'lumina_users_list_secure';
  static const String _sessionTokenKey = 'session_token';
  static const String _passwordPlainKey = 'lumina_password_plain';
  static const String _gradeKey = 'lumina_grade';

  String _hashPassword(String password) => sha256.convert(utf8.encode(password)).toString();

  /// The locally persisted unique user identifier, or `null` if no user is logged in.
  Future<String?> getUniqueUserId() async {
    return _secureStorage.read(key: _userIdKey);
  }

  /// The locally persisted username of the logged-in user, or `null` if not set.
  Future<String?> getLoggedUsername() async {
    return _secureStorage.read(key: _usernameKey);
  }

  /// The current session token used for authenticated API requests, or `null`.
  Future<String?> getSessionToken() async {
    return _secureStorage.read(key: _sessionTokenKey);
  }

  /// The grade level stored for the logged-in student, or `null`.
  Future<String?> getStudentGrade() async => _secureStorage.read(key: _gradeKey);

  /// Registers a new student account with the hub and persists credentials locally.
  ///
  /// Sends [username] and [password] to the `/register` endpoint. On success,
  /// stores the returned user id, session token, and a SHA-256 hashed copy of
  /// the password in secure storage for offline fallback. Returns `true` when
  /// registration succeeds, `false` on any network or server error.
  Future<bool> register({
    required String username,
    required String password,
    String? name,
  }) async {
    try {
      final response = await ApiClient.post('/register', data: {
        'username': username,
        'name': name ?? username,
        'password': password,
      });

      if (response.statusCode == null || response.statusCode! < 200 || response.statusCode! >= 300) return false;
      if (response.data == null || response.data is! Map) return false;
      final Map data = response.data;
      final String hubGeneratedId = data['id']?.toString() ?? '';
      final String? token = data['token']?.toString();
      
      List<Map<String, dynamic>> users = await _getUsers();
      final existing = users.indexWhere((u) => u['username'] == username);
      final newUser = {
        'username': username,
        'password': _hashPassword(password),
        'userId': hubGeneratedId,
      };
      
      if (existing >= 0) {
        users[existing] = newUser;
      } else {
        users.add(newUser);
      }
      await _secureStorage.write(key: _usersListKey, value: jsonEncode(users));
      
      await _secureStorage.write(key: _userIdKey, value: hubGeneratedId);
      await _secureStorage.write(key: _usernameKey, value: username);
      await _secureStorage.write(key: _passwordPlainKey, value: password);

      if (token != null) {
        await _secureStorage.write(key: _sessionTokenKey, value: token);
        ApiClient.setAuth(token);
      }
      
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Authenticates the student against the hub with offline fallback support.
  ///
  /// First attempts a local credential match against the persisted user list.
  /// On a new device, contacts the `/student/token` endpoint for hub-verified
  /// login. Returns `'ok'` on full success, `'local_only'` when the server is
  /// unreachable but credentials match locally, `'reset_required'` when the
  /// server indicates a password reset is needed, or `null` on failure.
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
        orElse: () => <String, dynamic>{},
      );

      if (localUser.isNotEmpty) {
        try {
          final loginResp = await ApiClient.post('/student/token', data: {'username': username, 'password': password});
          if (loginResp.data is Map) {
            final data = loginResp.data as Map;
            final token = data['token']?.toString() ?? '';
            if (token.isNotEmpty) {
              final grade = data['grade']?.toString() ?? '';
              if (grade.isNotEmpty) await _secureStorage.write(key: _gradeKey, value: grade);
              ApiClient.setAuth(token);
              _saveSession(localUser['userId'], username, password);
              return 'ok';
            }
          }
        } catch (_) {
          // Server unreachable - only allow offline access
          _saveSession(localUser['userId'], username, password);
          return 'local_only';
        }
        _saveSession(localUser['userId'], username, password);
        return 'local_only';
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
          final String? grade = respData['grade']?.toString();
          if (token != null && scholarId != null) {
            await _secureStorage.write(key: _sessionTokenKey, value: token);
            await _secureStorage.write(key: _userIdKey, value: scholarId);
            await _secureStorage.write(key: _passwordPlainKey, value: password);
            if (name != null) await _secureStorage.write(key: _usernameKey, value: name);
            if (grade != null && grade.isNotEmpty) await _secureStorage.write(key: _gradeKey, value: grade);
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

  Future<void> _saveSession(String id, String username, [String? password]) async {
    await _secureStorage.write(key: _userIdKey, value: id);
    await _secureStorage.write(key: _usernameKey, value: username);
    if (password != null) {
      await _secureStorage.write(key: _passwordPlainKey, value: password);
    }
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

  /// Logs the student out of the hub and wipes all locally stored credentials.
  Future<void> logout() async {
    try {
      await ApiClient.post('/logout');
    } catch (_) {}
    await _secureStorage.deleteAll();
  }

  /// Whether the session token was successfully refreshed against the hub.
  ///
  /// Reads the persisted username and password, re-authenticates via
  /// `/student/token`, and updates the stored session token. Returns `false`
  /// if no stored credentials exist or the hub is unreachable.
  Future<bool> refreshSession() async {
    try {
      final username = await _secureStorage.read(key: _usernameKey);
      final password = await _secureStorage.read(key: _passwordPlainKey);
      if (username == null || password == null) return false;
      final response = await ApiClient.post('/student/token', data: {
        'username': username,
        'password': password,
      });
      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map;
        final token = data['token']?.toString() ?? '';
        if (token.isNotEmpty) {
          await _secureStorage.write(key: _sessionTokenKey, value: token);
          ApiClient.setAuth(token);
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// The estimated size of the installed APK in bytes (hardcoded to 65 MB).
  ///
  /// Used by [WelcomePage] for storage calculations when no real APK path is
  /// available on the device.
  Future<int> getApkSize() async {
    return 65 * 1024 * 1024;
  }

  /// Persists the student's display name to secure storage.
  ///
  /// Used by [StudentProfilePage] when the user edits their profile name so the
  /// value survives app restarts and is available offline.
  Future<void> saveUsername(String name) async {
    await _secureStorage.write(key: _usernameKey, value: name);
  }

  /// Persists the student's grade level to secure storage.
  ///
  /// Used by [StudentProfilePage] when the user edits their grade so the value
  /// survives app restarts and is available offline.
  Future<void> saveGrade(String grade) async {
    await _secureStorage.write(key: _gradeKey, value: grade);
  }
}
