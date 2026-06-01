import 'package:dio/dio.dart';
import '../../auth/data/auth_service.dart';
import '../../../core/network/api_client.dart';

class TeacherRepository {
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    if (AuthService.isDemoMode) {
      ApiClient.setAuth('admin');
    } else {
      final username = await AuthService().getLoggedUsername();
      if (username != null) ApiClient.setAuth(username);
    }
    _initialized = true;
  }

  // --- Subjects ---
  static Future<List<Map<String, dynamic>>> getSubjects() async {
    await init();
    final resp = await ApiClient.get('/subjects');
    return List<Map<String, dynamic>>.from(resp.data ?? []);
  }

  static Future<void> createSubject(String name, String symbol, String className) async {
    await init();
    await ApiClient.post('/teacher/subjects', data: {
      'name': name,
      'symbol': symbol,
      'class_name': className,
    });
  }

  static Future<void> deleteSubject(String name, {String? transferTo}) async {
    await init();
    await ApiClient.post('/teacher/subjects/delete', data: {
      'name': name,
      if (transferTo != null) 'transfer_to': transferTo,
    });
  }

  // --- Resources ---
  static Future<List<Map<String, dynamic>>> getResources() async {
    await init();
    final resp = await ApiClient.get('/resources');
    return List<Map<String, dynamic>>.from(resp.data ?? []);
  }

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

  static Future<void> deleteResource(int id) async {
    await init();
    await ApiClient.delete('/teacher/resources/$id');
  }

  // --- ZIM ---
  static Future<Map<String, dynamic>> uploadZim(String filePath, String fileName) async {
    await init();
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    final resp = await ApiClient.post('/teacher/upload-zim', data: formData);
    return Map<String, dynamic>.from(resp.data ?? {});
  }

  static Future<Map<String, dynamic>> getLimits() async {
    await init();
    final resp = await ApiClient.get('/api/limits');
    return Map<String, dynamic>.from(resp.data ?? {});
  }

  // --- Server Files ---
  static Future<List<Map<String, dynamic>>> getServerFiles() async {
    await init();
    final resp = await ApiClient.get('/files');
    return List<Map<String, dynamic>>.from(resp.data ?? []);
  }

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
  static Future<List<Map<String, dynamic>>> getScholars() async {
    await init();
    final resp = await ApiClient.get('/teacher/scholars');
    return List<Map<String, dynamic>>.from(resp.data ?? []);
  }

  static Future<void> resetStudentPassword(String scholarId) async {
    await init();
    await ApiClient.post('/teacher/scholars/reset-password/$scholarId');
  }

  static Future<void> deleteStudent(String scholarId) async {
    await init();
    await ApiClient.delete('/teacher/scholars/$scholarId');
  }

  // --- Teacher Management ---
  static Future<List<Map<String, dynamic>>> getTeachers() async {
    await init();
    final resp = await ApiClient.get('/teachers');
    return List<Map<String, dynamic>>.from(resp.data ?? []);
  }

  static Future<void> forceResetTeacherPassword(String username) async {
    await init();
    await ApiClient.post('/teacher/reset-password/$username');
  }

  static Future<void> deleteTeacher(String username) async {
    await init();
    await ApiClient.delete('/teacher/profiles/$username');
  }

  // --- Admin ---
  static Future<void> disableDefaultAdmin() async {
    await init();
    await ApiClient.post('/teacher/disable-default-admin');
  }

  static Future<Map<String, dynamic>> getAdminSettings() async {
    await init();
    final resp = await ApiClient.get('/api/admin/settings');
    return Map<String, dynamic>.from(resp.data ?? {});
  }

  static Future<void> setLogRetention(String policy) async {
    await init();
    await ApiClient.post('/api/admin/settings', data: {'policy': policy});
  }

  static Future<List<String>> getAdminLog({int limit = 20}) async {
    await init();
    final resp = await ApiClient.get('/admin/log', queryParameters: {'limit': limit});
    final data = Map<String, dynamic>.from(resp.data ?? {});
    return List<String>.from(data['log'] ?? []);
  }

  static Future<String> downloadAdminLogs({String duration = 'all'}) async {
    await init();
    final resp = await ApiClient.get('/api/admin/logs/download',
        queryParameters: {'duration': duration});
    return resp.data?.toString() ?? '';
  }

  // --- Stats ---
  static Future<Map<String, dynamic>> getStats() async {
    await init();
    final resp = await ApiClient.get('/stats');
    return Map<String, dynamic>.from(resp.data ?? {});
  }
}
