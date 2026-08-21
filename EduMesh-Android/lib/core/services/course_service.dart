import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../models/course.dart';
import '../network/api_client.dart';
import '../storage/db_helper.dart';
import '../../features/auth/data/auth_service.dart';
import '../../shared/services/download_queue.dart';
import 'mutation_queue.dart';

/// Singleton service managing the course catalog, enrollment, progress tracking, and quizzes.
///
/// Wraps the `/api/courses` endpoints and local SQLite cache. Notifies
/// listeners on state changes so UI widgets rebuild automatically.
class CourseService extends ChangeNotifier {
  static final CourseService _instance = CourseService._internal();
  factory CourseService() => _instance;
  CourseService._internal();

  bool _loading = false;
  String? _error;

  /// Returns the current student's scholar ID, or '' if unavailable.
  Future<String> _getStudentId() async => (await AuthService().getUniqueUserId()) ?? '';

  List<Course> _cachedCourses = [];
  List<({Course course, Map<String, dynamic>? progress})> _enrolledCourses = [];

  bool get isLoading => _loading;

  /// The most recent error message, or `null` if no error.
  String? get error => _error;

  /// Locally cached course list from the last successful [fetchCatalog] call.
  List<Course> get cachedCourses => _cachedCourses;

  /// Courses the current student is enrolled in, with their progress rows.
  List<({Course course, Map<String, dynamic>? progress})> get enrolledCourses => _enrolledCourses;

  /// Fetches the course catalog from the hub, caches it locally, and returns it.
  Future<List<Course>> fetchCatalog() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final resp = await ApiClient.get('/api/courses');
      final data = resp.data;
      final List<dynamic> items;
      if (data is List) {
        items = data;
      } else if (data is Map && data['items'] is List) {
        items = data['items'] as List;
      } else {
        _loading = false;
        notifyListeners();
        return [];
      }
      final courses = items.map((e) => Course.fromJson(e as Map<String, dynamic>)).toList();
      final db = await DBHelper().database;
      await db.transaction((txn) async {
        await txn.delete('courses');
        for (final c in courses) {
          await txn.insert('courses', {
            'id': c.id,
            'title': c.title,
            'description': c.description ?? '',
            'subject': c.subject,
            'grade': c.grade,
            'language': c.language,
            'cover_image': c.coverImage ?? '',
            'published': c.published,
            'teacher_username': c.teacherUsername ?? '',
            'enrollment_count': c.enrollmentCount,
            'created_at': c.createdAt ?? '',
            'updated_at': c.updatedAt ?? '',
            'synced_at': DateTime.now().millisecondsSinceEpoch,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
      _cachedCourses = courses;
      _loading = false;
      _error = null;
      notifyListeners();
      return courses;
    } catch (e) {
      _loading = false;
      _error = e.toString();
      notifyListeners();
      return [];
    }
  }

  /// Fetches full course detail including resources, caches them locally, and returns the raw JSON.
  Future<Map<String, dynamic>?> fetchCourseDetail(String courseId) async {
    try {
      final resp = await ApiClient.get('/api/courses/$courseId');
      if (resp.statusCode == 200 && resp.data is Map) {
        final data = resp.data as Map<String, dynamic>;
        final db = await DBHelper().database;
        if (data['resources'] is List) {
          await db.transaction((txn) async {
            await txn.delete('course_resources', where: 'course_id = ?', whereArgs: [courseId]);
            for (final r in data['resources'] as List) {
              if (r is! Map) continue;
              await txn.insert('course_resources', {
                'id': (r['id'] ?? '').toString(),
                'course_id': courseId,
                'resource_type': (r['resource_type'] ?? 'textbook').toString(),
                'title': (r['title'] ?? '').toString(),
                'original_name': (r['original_name'] ?? '').toString(),
                'filename': (r['filename'] ?? '').toString(),
                'file_size': (r['file_size'] as num?)?.toInt() ?? 0,
                'page_count': (r['page_count'] as num?)?.toInt() ?? 0,
                'duration_seconds': (r['duration_seconds'] as num?)?.toInt() ?? 0,
                'position': (r['position'] as num?)?.toInt() ?? 0,
              }, conflictAlgorithm: ConflictAlgorithm.replace);
            }
          });
        }
        return data;
      }
      return null;
    } catch (e) {
      debugPrint('CourseService: fetchCourseDetail failed; $e');
      return null;
    }
  }

  /// Enrolls the current student in [courseId] and creates a local progress record.
  Future<bool> enroll(String courseId) async {
    try {
      final resp = await ApiClient.post('/api/courses/$courseId/enroll');
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final db = await DBHelper().database;
        final studentId = await AuthService().getUniqueUserId() ?? '';
        await db.insert('course_progress', {
          'student_id': studentId,
          'course_id': courseId,
          'current_position': 0,
          'completed_count': 0,
          'total_resources': 0,
          'completed': 0,
          'last_synced': DateTime.now().toIso8601String(),
          'enrolled_at': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('CourseService: enroll failed; $e');
      return false;
    }
  }

  /// Downloads all [resources] for [courseId] via [DownloadQueue], updating progress per resource.
  Future<bool> downloadCourse(String courseId, List<CourseResource> resources) async {
    final totalBytes = resources.fold<int>(0, (sum, r) => sum + r.fileSize);
    if (!await _hasEnoughStorage(totalBytes)) return false;
    int succeeded = 0;
    for (final resource in resources) {
      final String url;
      if (resource.filename != null && resource.filename!.contains('/')) {
        url = '${ApiClient.baseUrl}/files/${resource.filename}';
      } else {
        url = '${ApiClient.baseUrl}/files/courses/${resource.courseId}/resources/${resource.filename ?? resource.id}';
      }
      final ext = resource.filename != null ? '.${resource.filename!.split('.').last}' : '';
      final fileName = '${resource.id}$ext';
      try {
        await DownloadQueue().enqueue(
          resource.id, url, fileName,
          title: resource.title,
        );
        succeeded++;
      } catch (e) {
        debugPrint('CourseService: downloadCourse failed for ${resource.id}; $e');
      }
    }
    notifyListeners();
    return succeeded == resources.length;
  }

  /// Submits a quiz attempt via [MutationQueue] for offline support, then persists locally.
  Future<void> submitQuiz(String courseId, String resourceId, Map<String, dynamic> attempt) async {
    await MutationQueue().enqueue(
      '/api/courses/$courseId/quiz/$resourceId/submit',
      method: 'POST',
      body: attempt,
      priority: 'high',
    );
    await _saveQuizAttemptLocally(attempt);
  }

  /// Submits a standalone quiz attempt via [MutationQueue] for offline support.
  Future<void> submitStandaloneQuiz(String resourceId, Map<String, dynamic> attempt) async {
    await MutationQueue().enqueue(
      '/api/quiz-resource/$resourceId/submit',
      method: 'POST',
      body: attempt,
      priority: 'high',
    );
  }

  /// Updates the best score for a standalone quiz via [MutationQueue] for offline support.
  Future<void> updateStandaloneBestScore(String resourceId, double score, String attemptId) async {
    await MutationQueue().enqueue(
      '/api/quiz-resource/$resourceId/best-score',
      method: 'POST',
      body: {'score': score, 'attempt_id': attemptId},
      priority: 'normal',
    );
  }

  /// Returns all locally cached courses ordered by most recently synced.
  Future<List<Course>> getCachedCatalog() async {
    try {
      final db = await DBHelper().database;
      final rows = await db.query('courses', orderBy: 'synced_at DESC');
      return rows.map(_rowToCourse).toList();
    } catch (e) {
      debugPrint('CourseService: getCachedCatalog failed; $e');
      return [];
    }
  }

  /// Loads enrolled courses from local DB, fetching remote details for any not yet cached.
  Future<void> loadEnrolledCourses() async {
    try {
      final db = await DBHelper().database;
      final studentId = await _getStudentId();
      final progressRows = await db.query('course_progress',
        where: 'student_id = ?', whereArgs: [studentId]);

      // If empty (after data clear), restore from server first
      if (progressRows.isEmpty) {
        await _restoreEnrollmentsFromServer();
        final restoredRows = await db.query('course_progress',
          where: 'student_id = ?', whereArgs: [studentId]);
        if (restoredRows.isNotEmpty) {
          return loadEnrolledCourses(); // recurse with now-populated DB
        }
      }

      final result = <({Course course, Map<String, dynamic>? progress})>[];
      for (final pRow in progressRows.isEmpty ? await db.query('course_progress', where: 'student_id = ?', whereArgs: [studentId]) : progressRows) {
        final courseId = (pRow['course_id'] ?? '').toString();
        final courseRows = await db.query('courses', where: 'id = ?', whereArgs: [courseId]);
        if (courseRows.isNotEmpty) {
          final course = _rowToCourse(courseRows.first);
          result.add((course: course, progress: pRow));
        } else {
          final detail = await fetchCourseDetail(courseId);
          if (detail != null) {
            final course = Course.fromJson(detail);
            result.add((course: course, progress: pRow));
          }
        }
      }
      _enrolledCourses = result;
      notifyListeners();
    } catch (e) {
      debugPrint('CourseService: loadEnrolledCourses failed; $e');
    }
  }

  /// Restore enrolled courses from server (after data clear or fresh install).
  Future<void> _restoreEnrollmentsFromServer() async {
    try {
      final resp = await ApiClient.get('/student/enrolled-courses');
      if (resp.statusCode != 200 || resp.data is! Map) return;
      final data = resp.data as Map<String, dynamic>;
      final items = data['courses'] as List<dynamic>? ?? [];
      if (items.isEmpty) return;
      final db = await DBHelper().database;
      await db.transaction((txn) async {
        for (final item in items) {
          final m = item as Map<String, dynamic>;
          await txn.insert('courses', {
            'id': m['course_id'] ?? '',
            'title': m['title'] ?? '',
            'description': m['description'] ?? '',
            'subject': m['subject'] ?? '',
            'grade': m['grade'] ?? 0,
            'language': m['language'] ?? 'en',
            'cover_image': m['cover_image'] ?? '',
            'published': m['published'] ?? 0,
            'teacher_username': m['teacher_username'] ?? '',
            'enrollment_count': m['enrollment_count'] ?? 0,
            'created_at': m['created_at'] ?? '',
            'updated_at': m['updated_at'] ?? '',
            'synced_at': DateTime.now().millisecondsSinceEpoch,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          await txn.insert('course_progress', {
            'student_id': await _getStudentId(),
            'course_id': m['course_id'] ?? '',
            'current_position': m['current_position'] ?? 0,
            'completed_count': m['completed_count'] ?? 0,
            'total_resources': m['total_resources'] ?? 0,
            'completed': m['completed'] ?? 0,
            'last_synced': DateTime.now().toIso8601String(),
            'enrolled_at': m['enrolled_at'] ?? '',
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
    } catch (e) {
      debugPrint('CourseService: _restoreEnrollmentsFromServer failed; $e');
    }
  }

  /// Returns the count of courses marked as completed in local progress.
  Future<int> getCompletedCourseCount() async {
    try {
      final db = await DBHelper().database;
      final studentId = await _getStudentId();
      final result = await db.rawQuery('SELECT COUNT(*) AS cnt FROM course_progress WHERE completed = 1 AND student_id = ?', [studentId]);
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      debugPrint('CourseService: getCompletedCourseCount failed; $e');
      return 0;
    }
  }

  Future<bool> _hasEnoughStorage(int requiredBytes) async {
    if (requiredBytes > 500 * 1024 * 1024) return false;
    return true;
  }

  Future<void> _saveQuizAttemptLocally(Map<String, dynamic> attempt) async {
    final db = await DBHelper().database;
    await db.insert('quiz_attempts', {
      'id': attempt['attempt_id'],
      'student_id': attempt['student_id'] ?? '',
      'course_id': attempt['course_id'],
      'resource_id': attempt['resource_id'],
      'attempt_number': attempt['attempt_number'],
      'score': attempt['score'],
      'passed': attempt['passed'] ? 1 : 0,
      'answers_json': attempt['answers_json'] ?? '',
      'started_at': attempt['started_at'] ?? '',
      'submitted_at': attempt['submitted_at'] ?? '',
      'time_taken_seconds': attempt['time_taken_seconds'] ?? 0,
      'quiz_version': attempt['quiz_version'] ?? 1,
      'threshold_at_submission': attempt['threshold_at_submission'] ?? 0.0,
      'sync_status': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Course _rowToCourse(Map<String, dynamic> row) {
    return Course(
      id: (row['id'] ?? '').toString(),
      title: (row['title'] ?? '').toString(),
      description: (row['description'] ?? '').toString(),
      subject: (row['subject'] ?? '').toString(),
      grade: (row['grade'] as num?)?.toInt() ?? 0,
      language: (row['language'] ?? 'en').toString(),
      coverImage: (row['cover_image'] ?? '').toString(),
      published: (row['published'] as num?)?.toInt() ?? 0,
      teacherUsername: (row['teacher_username'] ?? '').toString(),
      enrollmentCount: (row['enrollment_count'] as num?)?.toInt() ?? 0,
      createdAt: (row['created_at'] ?? '').toString(),
      updatedAt: (row['updated_at'] ?? '').toString(),
    );
  }
}
