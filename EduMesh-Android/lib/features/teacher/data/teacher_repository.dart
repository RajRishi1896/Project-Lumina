import 'package:dio/dio.dart';
import '../../auth/data/auth_service.dart';
import '../../../core/network/api_client.dart';

/// Repository for teacher-facing API operations.
///
/// Provides static methods for subjects, resources, ZIM uploads, student/teacher
/// management, admin settings, and server statistics. All methods auto-initialize
/// the session token via [init] on first call.
class TeacherRepository {
  static bool _initialized = false;

  /// Ensures the session token is loaded before any API call.
  ///
  /// Retrieves the session token from [AuthService] and sets it on the
  /// shared [ApiClient] singleton. Subsequent calls are no-ops.
  static Future<void> init() async {
    if (_initialized) return;
    final token = await AuthService().getSessionToken();
    if (token != null) ApiClient.setAuth(token);
    _initialized = true;
  }

  // --- Subjects ---

  /// The list of all subjects from the server.
  ///
  /// Each entry is a map with keys such as `name`, `symbol`, and `class_name`.
  static Future<List<Map<String, dynamic>>> getSubjects() async {
    await init();
    final resp = await ApiClient.get('/subjects');
    return List<Map<String, dynamic>>.from(resp.data ?? []);
  }

  /// Creates a new subject on the server.
  ///
  /// [name] is the display name, [symbol] is the short code, and [className]
  /// is the grade or class this subject belongs to.
  static Future<void> createSubject(String name, String symbol, String className) async {
    await init();
    await ApiClient.post('/teacher/subjects', data: {
      'name': name,
      'symbol': symbol,
      'class_name': className,
    });
  }

  /// Deletes a subject by [name], optionally transferring its resources to
  /// another subject named [transferTo].
  static Future<void> deleteSubject(String name, {String? transferTo}) async {
    await init();
    await ApiClient.post('/teacher/subjects/delete', data: {
      'name': name,
      if (transferTo != null) 'transfer_to': transferTo,
    });
  }

  // --- Resources ---

  /// The list of all resources from the server.
  ///
  /// Each entry is a map with keys such as `id`, `title`, `type`, and `subject`.
  static Future<List<Map<String, dynamic>>> getResources() async {
    await init();
    final resp = await ApiClient.get('/resources');
    return List<Map<String, dynamic>>.from(resp.data ?? []);
  }

  /// Uploads a new resource file to the server.
  ///
  /// [filePath] is the local path to the file and [fileName] is the desired
  /// name on the server. [title], [type], and [subject] describe the resource.
  static Future<void> uploadResource({
    required String title,
    required String type,
    required String subject,
    required String filePath,
    required String fileName,
  }) async {
    await init();
    final formData = FormData.fromMap({
      'title': title,
      'type': type,
      'subject': subject,
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    await ApiClient.post('/teacher/upload', data: formData);
  }

  /// Deletes a resource by its [id].
  static Future<void> deleteResource(int id) async {
    await init();
    await ApiClient.delete('/teacher/resources/$id');
  }

  // --- ZIM ---

  /// Uploads a ZIM file to the server and returns the server response map.
  static Future<Map<String, dynamic>> uploadZim(String filePath, String fileName) async {
    await init();
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    final resp = await ApiClient.post('/teacher/upload-zim', data: formData);
    return Map<String, dynamic>.from(resp.data ?? {});
  }

  /// Disk-space and usage limits from the server.
  static Future<Map<String, dynamic>> getLimits() async {
    await init();
    final resp = await ApiClient.get('/api/limits');
    return Map<String, dynamic>.from(resp.data ?? {});
  }

  // --- Server Files ---

  /// The list of files already present on the server's file system.
  static Future<List<Map<String, dynamic>>> getServerFiles() async {
    await init();
    final resp = await ApiClient.get('/api/files');
    return List<Map<String, dynamic>>.from(resp.data ?? []);
  }

  /// Imports a file already on the server into the resource catalog.
  ///
  /// [filename] must match a file present on the server. [title], [type],
  /// and [subject] describe the imported resource.
  static Future<void> importServerFile({
    required String filename,
    required String title,
    required String type,
    required String subject,
  }) async {
    await init();
    await ApiClient.post('/teacher/import-server-file', queryParameters: {
      'filename': filename,
      'title': title,
      'type': type,
      'subject': subject,
    });
  }

  // --- Change Password ---

  /// Changes the password for a teacher account.
  ///
  /// Requires the current [oldPassword] and the desired [newPassword].
  static Future<void> changePassword({
    required String username,
    required String oldPassword,
    required String newPassword,
  }) async {
    await init();
    await ApiClient.post('/teacher/change-password', data: {
      'username': username,
      'old_password': oldPassword,
      'new_password': newPassword,
    });
  }

  // --- Create Teacher Profile ---

  /// Creates a new teacher profile on the server.
  ///
  /// [username] and [password] are required; [name] and [department] are
  /// optional human-readable fields.
  static Future<void> createTeacherProfile({
    required String username,
    required String password,
    String? name,
    String? department,
  }) async {
    await init();
    await ApiClient.post('/teacher/profiles', data: {
      'username': username,
      'password': password,
      if (name != null && name.isNotEmpty) 'name': name,
      if (department != null && department.isNotEmpty) 'department': department,
    });
  }

  // --- Scholars (Students) ---

  /// The list of all student (scholar) accounts.
  ///
  /// Each entry is a map with keys such as `id`, `name`, and `grade`.
  static Future<List<Map<String, dynamic>>> getScholars() async {
    await init();
    final resp = await ApiClient.get('/teacher/scholars');
    return List<Map<String, dynamic>>.from(resp.data ?? []);
  }

  /// Resets a student's password, returning it to the default.
  static Future<void> resetStudentPassword(String scholarId) async {
    await init();
    await ApiClient.post('/teacher/scholars/reset-password/$scholarId');
  }

  /// Deletes a student account by [scholarId].
  static Future<void> deleteStudent(String scholarId) async {
    await init();
    await ApiClient.delete('/teacher/scholars/$scholarId');
  }

  // --- Teacher Management ---

  /// The list of all teacher profiles on the server.
  static Future<List<Map<String, dynamic>>> getTeachers() async {
    await init();
    final resp = await ApiClient.get('/teachers');
    return List<Map<String, dynamic>>.from(resp.data ?? []);
  }

  /// Forces a password reset for a teacher account by [username].
  static Future<void> forceResetTeacherPassword(String username) async {
    await init();
    await ApiClient.post('/teacher/reset-password/$username');
  }

  /// Deletes a teacher profile by [username].
  static Future<void> deleteTeacher(String username) async {
    await init();
    await ApiClient.delete('/teacher/profiles/$username');
  }

  // --- Admin ---

  /// Disables the default admin account for security.
  static Future<void> disableDefaultAdmin() async {
    await init();
    await ApiClient.post('/teacher/disable-default-admin');
  }

  /// The current admin settings from the server.
  static Future<Map<String, dynamic>> getAdminSettings() async {
    await init();
    final resp = await ApiClient.get('/api/admin/settings');
    return Map<String, dynamic>.from(resp.data ?? {});
  }

  /// Sets the log retention [policy] on the server.
  static Future<void> setLogRetention(String policy) async {
    await init();
    await ApiClient.post('/api/admin/settings', data: {'policy': policy});
  }

  /// The admin audit log, up to [limit] entries.
  static Future<List<String>> getAdminLog({int limit = 20}) async {
    await init();
    final resp = await ApiClient.get('/admin/log', queryParameters: {'limit': limit});
    final data = Map<String, dynamic>.from(resp.data ?? {});
    return List<String>.from(data['log'] ?? []);
  }

  /// Downloads the full admin audit logs as a string.
  ///
  /// [duration] filters by time range (e.g. `'all'`, `'7d'`, `'30d'`).
  static Future<String> downloadAdminLogs({String duration = 'all'}) async {
    await init();
    final resp = await ApiClient.get('/api/admin/logs/download',
        queryParameters: {'duration': duration});
    return resp.data?.toString() ?? '';
  }

  // --- Stats ---

  /// Server statistics including resource counts, storage usage, etc.
  static Future<Map<String, dynamic>> getStats() async {
    await init();
    final resp = await ApiClient.get('/stats');
    return Map<String, dynamic>.from(resp.data ?? {});
  }

  // --- Student Monitor ---

  /// Lists all students with aggregated study stats, optionally filtered by [grade].
  static Future<List<Map<String, dynamic>>> getStudents({String? grade}) async {
    await init();
    final params = <String, dynamic>{};
    if (grade != null && grade.isNotEmpty) params['grade'] = grade;
    final resp = await ApiClient.get('/teacher/students', queryParameters: params);
    final data = Map<String, dynamic>.from(resp.data ?? {});
    return List<Map<String, dynamic>>.from(data['students'] ?? []);
  }

  /// Detailed analytics for a specific student by [scholarId].
  static Future<Map<String, dynamic>> getStudentAnalytics(String scholarId) async {
    await init();
    final resp = await ApiClient.get('/teacher/student/$scholarId/analytics');
    return Map<String, dynamic>.from(resp.data ?? {});
  }

  /// Paginated activity log for a specific student by [scholarId].
  static Future<Map<String, dynamic>> getStudentActivity(String scholarId, {int limit = 50, int offset = 0}) async {
    await init();
    final resp = await ApiClient.get('/teacher/student/$scholarId/activity', queryParameters: {
      'limit': limit,
      'offset': offset,
    });
    return Map<String, dynamic>.from(resp.data ?? {});
  }
}
