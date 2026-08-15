import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/network/api_client.dart';

/// A singleton service managing student authentication and secure credential storage.
///
/// Wraps [FlutterSecureStorage] to persist user id, username, session token,
/// grade, and a local user database. Performs hub-verified login with offline
/// fallback using the stored session token.
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final _secureStorage = const FlutterSecureStorage();
  
  static const String _userIdKey = 'lumina_unique_user_id';
  static const String _usernameKey = 'lumina_username';
  static const String _usersListKey = 'lumina_users_list_secure';
  static const String _sessionTokenKey = 'session_token';
  static const String _refreshTokenKey = 'lumina_refresh_token';
  static const String _persistentKeyKey = 'lumina_persistent_key';
  static const String _gradeKey = 'lumina_grade';
  static const String _displayNameKey = 'lumina_display_name';

  /// Extracts a human-readable error message from a server response.
  String _extractError(dynamic response) {
    if (response.data is Map) {
      final data = response.data as Map;
      if (data['detail'] != null) return data['detail'].toString();
      if (data['message'] != null) return data['message'].toString();
      if (data['error'] != null) return data['error'].toString();
    }
    return 'Registration failed (HTTP ${response.statusCode})';
  }

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

  /// The grade level, defaulting to "General" if not set.
  Future<String> getGradeOrDefault() async {
    final g = await _secureStorage.read(key: _gradeKey);
    return (g != null && g.isNotEmpty) ? g : 'General';
  }

  /// Registers a new student account with the hub and persists credentials locally.
  ///
  /// Sends [username] and [password] to the `/register` endpoint. On success,
  /// stores the returned user id, session token, and username in secure
  /// storage for offline recognition. Returns `null` on success, or an error
  /// message string on failure.
  Future<String?> register({
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

      if (response.statusCode == null || response.statusCode! < 200 || response.statusCode! >= 300) {
        final detail = _extractError(response);
        return detail;
      }
      if (response.data == null || response.data is! Map) return 'Unexpected server response';
      final Map data = response.data;
      final String hubGeneratedId = data['id']?.toString() ?? '';
      final String? token = data['token']?.toString();
      final String? refreshToken = data['refresh_token']?.toString();
      final String? persistentKey = data['persistent_key']?.toString();

      List<Map<String, dynamic>> users = await _getUsers();
      final existing = users.indexWhere((u) => u['username'] == username);
      final newUser = {
        'username': username,
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
      if (token != null) {
        await _secureStorage.write(key: _sessionTokenKey, value: token);
        ApiClient.setAuth(token);
      }

      if (refreshToken != null) await _secureStorage.write(key: _refreshTokenKey, value: refreshToken);
      if (persistentKey != null) await _secureStorage.write(key: _persistentKeyKey, value: persistentKey);

      return null;
    } catch (e) {
      if (e is DioException && e.response != null) {
        return _extractError(e.response!);
      }
      return 'Registration failed. Check hub connection.';
    }
  }

  /// Authenticates the student against the hub with offline fallback support.
  ///
  /// First attempts hub-verified login via `/student/token`. When the hub is
  /// unreachable and the username is known to this device, falls back to the
  /// stored session token (offline login). Returns `'ok'` on full success,
  /// `'local_only'` when the server is unreachable but the stored token is
  /// available, `'reset_required'` when the server indicates a password reset
  /// is needed, or `null` on failure.
  Future<String?> login({
    required String username,
    required String password,
  }) async {
    try {
      // 1. Try hub-verified login first
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
            await _secureStorage.write(key: _usernameKey, value: username);
            final refreshToken = respData['refresh_token']?.toString();
            final persistentKey = respData['persistent_key']?.toString();
            if (refreshToken != null && refreshToken.isNotEmpty) await _secureStorage.write(key: _refreshTokenKey, value: refreshToken);
            if (persistentKey != null && persistentKey.isNotEmpty) await _secureStorage.write(key: _persistentKeyKey, value: persistentKey);
            if (name != null && name.isNotEmpty) {
              await _secureStorage.write(key: _displayNameKey, value: name);
            }
            if (grade != null && grade.isNotEmpty) await _secureStorage.write(key: _gradeKey, value: grade);
            ApiClient.setAuth(token);
            await _rememberUser(username, scholarId);
            return resetReq ? 'reset_required' : 'ok';
          }
        }
      } on DioException catch (e) {
        // Server unreachable (no status code) -- try offline login below.
        if (e.response?.statusCode != null) return null;
      } catch (_) {
        // Non-Dio failure (e.g. timeout) -- try offline login below.
      }

      // 2. Offline fallback: known username on this device + stored token
      final users = await _getUsers();
      final known = users.any((u) => u['username'] == username);
      final storedToken = await _secureStorage.read(key: _sessionTokenKey);
      if (known && storedToken != null && storedToken.isNotEmpty) {
        final userId = users.firstWhere(
          (u) => u['username'] == username,
          orElse: () => <String, dynamic>{},
        )['userId']?.toString();
        if (userId != null && userId.isNotEmpty) {
          ApiClient.setAuth(storedToken);
          await _saveSession(userId, username);
          return 'local_only';
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Records a successfully verified username/userId pair in the local user
  /// list so offline login can recognise this device.
  Future<void> _rememberUser(String username, String userId) async {
    try {
      final users = await _getUsers();
      final existing = users.indexWhere((u) => u['username'] == username);
      if (existing >= 0) {
        users[existing] = {'username': username, 'userId': userId};
      } else {
        users.add({'username': username, 'userId': userId});
      }
      await _secureStorage.write(key: _usersListKey, value: jsonEncode(users));
    } catch (_) {}
  }

  /// The stored display name for the logged-in student, or `null` if not set.
  Future<String?> getDisplayName() async {
    return _secureStorage.read(key: _displayNameKey);
  }

  /// Caches the username locally without hitting the server.
  Future<void> cacheUsername(String username) async {
    await _secureStorage.write(key: _usernameKey, value: username);
  }

  /// Caches the display name locally without hitting the server.
  Future<void> cacheDisplayName(String name) async {
    await _secureStorage.write(key: _displayNameKey, value: name);
  }

  /// Updates the student's display name on the hub and persists it locally.
  Future<bool> setDisplayName(String name) async {
    await _secureStorage.write(key: _displayNameKey, value: name);
    try {
      await ApiClient.post('/student/profile/update', data: {'name': name});
      return true;
    } catch (_) {
      return false;
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

  /// Logs the student out of the hub and wipes all locally stored credentials.
  Future<void> logout() async {
    try {
      await ApiClient.post('/logout');
    } catch (_) { } await _secureStorage.deleteAll();
  }

  /// Refreshes the session token using the stored refresh token.
  ///
  /// POSTs the refresh_token to `/student/refresh-token`. On success, stores
  /// the new token chain (session, refresh, persistent, encryption). Falls
  /// back to [renewSession] if the refresh token is expired or invalid.
  /// Returns `true` if the session was successfully refreshed.
  Future<bool> refreshSession() async {
    try {
      final refreshToken = await _secureStorage.read(key: _refreshTokenKey);
      if (refreshToken == null || refreshToken.isEmpty) return renewSession();
      final response = await ApiClient.post('/student/refresh-token', data: {
        'refresh_token': refreshToken,
      });
      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map;
        final token = data['token']?.toString() ?? '';
        if (token.isNotEmpty) {
          await _secureStorage.write(key: _sessionTokenKey, value: token);
          final newRefreshToken = data['refresh_token']?.toString();
          final persistentKey = data['persistent_key']?.toString();
          if (newRefreshToken != null && newRefreshToken.isNotEmpty) {
            await _secureStorage.write(key: _refreshTokenKey, value: newRefreshToken);
          }
          if (persistentKey != null && persistentKey.isNotEmpty) {
            await _secureStorage.write(key: _persistentKeyKey, value: persistentKey);
          }
          ApiClient.setAuth(token);
          return true;
        }
      }
      return renewSession();
    } catch (_) {
      return renewSession();
    }
  }

  /// Renews the session using the persistent key.
  ///
  /// POSTs the persistent_key to `/student/renew-session`. On success, stores
  /// the new token chain. Returns `true` on success, `false` if the persistent
  /// key is expired or the hub is unreachable (user must re-login).
  Future<bool> renewSession() async {
    try {
      final persistentKey = await _secureStorage.read(key: _persistentKeyKey);
      if (persistentKey == null || persistentKey.isEmpty) return false;
      final response = await ApiClient.post('/student/renew-session', data: {
        'persistent_key': persistentKey,
      });
      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map;
        final token = data['token']?.toString() ?? '';
        if (token.isNotEmpty) {
          await _secureStorage.write(key: _sessionTokenKey, value: token);
          final newRefreshToken = data['refresh_token']?.toString();
          final newPersistentKey = data['persistent_key']?.toString();
          if (newRefreshToken != null && newRefreshToken.isNotEmpty) {
            await _secureStorage.write(key: _refreshTokenKey, value: newRefreshToken);
          }
          if (newPersistentKey != null && newPersistentKey.isNotEmpty) {
            await _secureStorage.write(key: _persistentKeyKey, value: newPersistentKey);
          }
          ApiClient.setAuth(token);
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Persists the student's grade level to secure storage.
  ///
  /// Used by [StudentProfilePage] when the user edits their grade so the value
  /// survives app restarts and is available offline.
  Future<void> saveGrade(String grade) async {
    await _secureStorage.write(key: _gradeKey, value: grade);
  }
}
