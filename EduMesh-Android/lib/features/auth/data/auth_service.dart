import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/db_helper.dart';
import '../../../core/services/activity_tracker.dart';
import '../../../shared/services/download_queue.dart';
import '../../../shared/widgets/mini_player_controller.dart';

/// A singleton service managing student authentication and secure credential storage.
///
/// Wraps [FlutterSecureStorage] to persist user id, username, session token,
/// grade, and a local user database. Performs hub-verified login with offline
/// fallback using the stored session token.
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  /// Monotonic counter bumped whenever the active profile's data is purged
  /// (logout or profile switch). Background operations snapshot it at start
  /// and re-check before writing: a changed value means their data now
  /// belongs to a different student's session.
  static int _sessionGeneration = 0;

  /// The current session generation (see [_sessionGeneration]).
  static int get sessionGeneration => _sessionGeneration;

  final _secureStorage = const FlutterSecureStorage();
  
  static const String _userIdKey = 'lumina_unique_user_id';
  static const String _usernameKey = 'lumina_username';
  static const String _usersListKey = 'lumina_users_list_secure';
  static const String _sessionTokenKey = 'session_token';
  static const String _refreshTokenKey = 'lumina_refresh_token';
  static const String _persistentKeyKey = 'lumina_persistent_key';
  static const String _gradeKey = 'lumina_grade';
  static const String _displayNameKey = 'lumina_display_name';

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
        if (response.statusCode == 409) return 'username_taken';
        return 'registration_failed';
      }
      if (response.data == null || response.data is! Map) return 'registration_failed';
      final Map data = response.data;
      final String hubGeneratedId = data['id']?.toString() ?? '';
      final String? token = data['token']?.toString();
      final String? refreshToken = data['refresh_token']?.toString();
      final String? persistentKey = data['persistent_key']?.toString();

      // Registration from the picker's "Add Profile" flow switches accounts:
      // drop the outgoing student's pending state before activating the new
      // one, or it flushes under the new profile's token.
      await _purgeIfSwitching(username);

      await _rememberUser(
        username,
        hubGeneratedId,
        token: token,
        refreshToken: refreshToken,
        persistentKey: persistentKey,
        displayName: name,
      );
      
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
        if (e.response!.statusCode == 409) return 'username_taken';
        return 'registration_failed';
      }
      return 'registration_failed';
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
            // Login after "Add Profile" switches accounts: purge the
            // outgoing student's pending state before their queues can
            // flush under the incoming profile's token.
            await _purgeIfSwitching(username);
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
            await _rememberUser(username, scholarId, token: token, refreshToken: refreshToken, persistentKey: persistentKey, displayName: name, grade: grade);
            return resetReq ? 'reset_required' : 'ok';
          }
        }
      } on DioException catch (e) {
        // Server unreachable (no status code): try offline login below.
        if (e.response?.statusCode != null) return null;
      } catch (_) {
        // Non-Dio failure (e.g. timeout): try offline login below.
      }

      // 2. Offline fallback: the MATCHED profile's own stored token. Never
      // reuse the active session token here: it may belong to a different
      // profile, which would authenticate the entered user with another
      // child's credentials (split-brain).
      final users = await _getUsers();
      final profile = users.firstWhere(
        (u) => u['username'] == username,
        orElse: () => <String, dynamic>{},
      );
      final storedToken = profile['token']?.toString() ?? '';
      final userId = profile['userId']?.toString() ?? '';
      if (storedToken.isNotEmpty && userId.isNotEmpty) {
        await _purgeIfSwitching(username);
        ApiClient.setAuth(storedToken);
        await _secureStorage.write(key: _sessionTokenKey, value: storedToken);
        await _saveSession(userId, username);
        return 'local_only';
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Records a successfully verified username/userId pair in the local user
  /// list so offline login can recognise this device. Merges into an existing
  /// entry so previously stored tokens and metadata are preserved.
  Future<void> _rememberUser(
    String username,
    String userId, {
    String? token,
    String? refreshToken,
    String? persistentKey,
    String? displayName,
    String? grade,
  }) async {
    try {
      final users = await _getUsers();
      _upsertProfile(users, {
        'username': username,
        'userId': userId,
        if (token != null && token.isNotEmpty) 'token': token,
        if (refreshToken != null && refreshToken.isNotEmpty) 'refreshToken': refreshToken,
        if (persistentKey != null && persistentKey.isNotEmpty) 'persistentKey': persistentKey,
        if (displayName != null && displayName.isNotEmpty) 'displayName': displayName,
        if (grade != null && grade.isNotEmpty) 'grade': grade,
      });
      await _saveUsers(users);
    } catch (_) {}
  }

  /// Inserts [entry] into [users], merging into an existing entry with the
  /// same `userId` (falling back to `username` when the id is missing).
  void _upsertProfile(List<Map<String, dynamic>> users, Map<String, dynamic> entry) {
    final userId = entry['userId']?.toString() ?? '';
    final username = entry['username']?.toString() ?? '';
    final index = users.indexWhere((u) {
      final id = u['userId']?.toString() ?? '';
      return (userId.isNotEmpty && id == userId) ||
          (userId.isEmpty && u['username'] == username);
    });
    if (index >= 0) {
      users[index] = {...users[index], ...entry};
    } else {
      users.add({...entry});
    }
  }

  /// Persists the known-profiles list to secure storage.
  Future<void> _saveUsers(List<Map<String, dynamic>> users) async {
    await _secureStorage.write(key: _usersListKey, value: jsonEncode(users));
  }

  /// The locally known student profiles (identity fields only, never tokens).
  ///
  /// Each entry contains `username`, `userId`, and optionally `displayName`.
  /// Used by the profile picker so children can switch without a password.
  Future<List<Map<String, dynamic>>> getKnownProfiles() async {
    final users = await _getUsers();
    final result = <Map<String, dynamic>>[];
    for (final u in users) {
      final userId = u['userId']?.toString() ?? '';
      final username = u['username']?.toString() ?? '';
      if (userId.isEmpty && username.isEmpty) continue;
      final displayName = u['displayName']?.toString() ?? '';
      result.add({
        'username': username,
        'userId': userId,
        if (displayName.isNotEmpty) 'displayName': displayName,
      });
    }
    return result;
  }

  /// Switches the active profile to the student identified by [userId].
  ///
  /// Works fully offline: restores that profile's identity and credentials
  /// from secure storage and re-arms the API auth header. Returns `false`
  /// when [userId] is not a known profile on this device.
  Future<bool> switchToProfile(String userId) async {
    final users = await _getUsers();
    Map<String, dynamic>? profile;
    for (final u in users) {
      if (u['userId']?.toString() == userId) {
        profile = u;
        break;
      }
    }
    if (profile == null || profile['username'] == null) return false;

    // The profile picker switches without going through logout: purge the
    // outgoing student's pending state BEFORE activating the target so it
    // can never flush under the new profile's token.
    await _purgeActiveProfileData();

    await _secureStorage.write(key: _userIdKey, value: userId);
    await _secureStorage.write(key: _usernameKey, value: profile['username'].toString());
    final token = profile['token']?.toString() ?? '';
    final fields = <String, String>{
      _sessionTokenKey: token,
      _refreshTokenKey: profile['refreshToken']?.toString() ?? '',
      _persistentKeyKey: profile['persistentKey']?.toString() ?? '',
      _gradeKey: profile['grade']?.toString() ?? '',
      _displayNameKey: profile['displayName']?.toString() ?? '',
    };
    for (final entry in fields.entries) {
      if (entry.value.isNotEmpty) {
        await _secureStorage.write(key: entry.key, value: entry.value);
      } else {
        await _secureStorage.delete(key: entry.key);
      }
    }
    if (token.isNotEmpty) {
      ApiClient.setAuth(token);
    } else {
      ApiClient.clearAuth();
    }
    return true;
  }

  /// Removes the active profile (tokens and its list entry) from the device,
  /// keeping all other known profiles switchable. Called by [logout].
  Future<void> _removeActiveProfile() async {
    await _purgeActiveProfileData();
    try {
      final activeId = await _secureStorage.read(key: _userIdKey);
      final activeUsername = await _secureStorage.read(key: _usernameKey);
      final users = await _getUsers();
      users.removeWhere((u) {
        final id = u['userId']?.toString() ?? '';
        return (activeId != null && activeId.isNotEmpty && id == activeId) ||
            (activeId == null && u['username'] == activeUsername);
      });
      await _saveUsers(users);
    } catch (_) {}
    for (final key in [
      _userIdKey,
      _usernameKey,
      _sessionTokenKey,
      _refreshTokenKey,
      _persistentKeyKey,
      _gradeKey,
      _displayNameKey,
    ]) {
      try {
        await _secureStorage.delete(key: key);
      } catch (_) {}
    }
    ApiClient.clearAuth();
  }

  /// Drops all per-profile local state: pending mutations/downloads, the
  /// activity table, bookmarks, flashcard reviews/submissions, cached
  /// analytics/events prefs, and in-memory session and queue state. Without
  /// this, one student's queued writes would sync under another student's
  /// token after a logout or profile switch.
  Future<void> _purgeActiveProfileData() async {
    // Bump FIRST so any in-flight operation that snapshots the generation
    // sees the new value even while the purge below is still running.
    _sessionGeneration++;
    try {
      final db = await DBHelper().database;
      await db.transaction((txn) async {
        await txn.delete('pending_mutations');
        await txn.delete('pending_downloads');
        await txn.delete('activity');
        await txn.delete('bookmarks');
        await txn.delete('flashcard_reviews_local');
        await txn.delete('flashcard_submissions_local');
      });
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('local_events');
      await prefs.remove('cached_analytics');
      await prefs.remove('active_study_session');
    } catch (_) {}
    ActivityTracker().resetSessionState();
    DownloadQueue().clear();
    MiniPlayerController().stop();
  }

  /// Purges per-profile state only when [username] differs from the
  /// currently active profile, so re-authenticating as the same student
  /// keeps their own queued work intact.
  Future<void> _purgeIfSwitching(String username) async {
    try {
      final active = await _secureStorage.read(key: _usernameKey);
      if (active != null && active == username) return;
    } catch (_) {}
    await _purgeActiveProfileData();
  }

  /// Logs out locally without any network call: clears the active profile's
  /// credentials and per-profile state only.
  ///
  /// Used by [ApiClient]'s 401 terminal path, where a networked logout could
  /// 401 again and re-enter the interceptor (circular await / app freeze).
  Future<void> logoutLocal() async {
    await _removeActiveProfile();
  }

  /// Logs the student out of the hub and removes only the active profile
  /// from this device. Other known profiles stay switchable.
  Future<void> logout() async {
    try {
      await ApiClient.post('/logout');
    } catch (_) {}
    await _removeActiveProfile();
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
    await _patchActiveProfile({'displayName': name});
  }

  /// Updates the student's display name on the hub and persists it locally.
  Future<bool> setDisplayName(String name) async {
    await _secureStorage.write(key: _displayNameKey, value: name);
    await _patchActiveProfile({'displayName': name});
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

  /// Consecutive [_getUsers] failures; 2 in a row means the users-list entry
  /// is genuinely corrupted (e.g. Android Keystore broken after lock-screen
  /// removal), not a transient read error.
  static int _usersListReadFailures = 0;

  Future<List<Map<String, dynamic>>> _getUsers() async {
    try {
      final String? usersJson = await _secureStorage.read(key: _usersListKey);
      if (usersJson == null) {
        _usersListReadFailures = 0;
        return [];
      }
      final users = List<Map<String, dynamic>>.from(jsonDecode(usersJson));
      _usersListReadFailures = 0;
      return users;
    } catch (e) {
      _usersListReadFailures++;
      // EDGE CASE: If Android Keystore is corrupted (e.g. user removed lock
      // screen PIN), read() throws on every call. Drop ONLY the users list,
      // and only after repeated failures: a single transient error must not
      // wipe every profile, and deleteAll() would nuke the active session.
      if (_usersListReadFailures >= 2) {
        _usersListReadFailures = 0;
        try { await _secureStorage.delete(key: _usersListKey); } catch (_) {}
      }
      return [];
    }
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
          await _patchActiveProfile({'token': token, 'refreshToken': newRefreshToken ?? '', 'persistentKey': persistentKey ?? ''});
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
          await _patchActiveProfile({'token': token, 'refreshToken': newRefreshToken ?? '', 'persistentKey': newPersistentKey ?? ''});
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
    await _patchActiveProfile({'grade': grade});
  }

  /// Mirrors refreshed credentials or edited metadata ([patch]) into the
  /// active profile's list entry so [switchToProfile] and the profile picker
  /// see fresh values. Empty values are skipped.
  Future<void> _patchActiveProfile(Map<String, String> patch) async {
    try {
      final activeId = await _secureStorage.read(key: _userIdKey);
      if (activeId == null || activeId.isEmpty) return;
      final users = await _getUsers();
      final index = users.indexWhere((u) => u['userId']?.toString() == activeId);
      if (index < 0) return;
      patch.forEach((key, value) {
        if (value.isNotEmpty) users[index][key] = value;
      });
      await _saveUsers(users);
    } catch (_) {}
  }
}
