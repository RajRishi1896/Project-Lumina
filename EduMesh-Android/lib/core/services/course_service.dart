import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../models/course.dart';
import '../network/api_client.dart';
import '../storage/db_helper.dart';
import '../../shared/services/download_queue.dart';
import 'mutation_queue.dart';

class CourseService extends ChangeNotifier {
  static final CourseService _instance = CourseService._internal();
  factory CourseService() => _instance;
  CourseService._internal();

  bool _loading = false;
  String? _error;
  List<Course> _cachedCourses = [];
  List<({Course course, Map<String, dynamic>? progress})> _enrolledCourses = [];
  final Map<String, double> _downloadProgress = {};

  bool get isLoading => _loading;
  String? get error => _error;
  List<Course> get cachedCourses => _cachedCourses;
  List<({Course course, Map<String, dynamic>? progress})> get enrolledCourses => _enrolledCourses;
  Map<String, double> get downloadProgress => Map.unmodifiable(_downloadProgress);

  Future<List<Course>> fetchCatalog({String? subject, int? grade, String? language, String? search, int page = 1, int perPage = 20}) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final qp = <String, dynamic>{
        'page': page,
        'per_page': perPage,
      };
      if (subject != null && subject.isNotEmpty) qp['subject'] = subject;
      if (grade != null) qp['grade'] = grade;
      if (language != null && language.isNotEmpty) qp['language'] = language;
      if (search != null && search.isNotEmpty) qp['search'] = search;
      final resp = await ApiClient.get('/api/courses', queryParameters: qp);
      final data = resp.data;
      if (data is! List) {
        _loading = false;
        notifyListeners();
        return [];
      }
      final courses = data.map((e) => Course.fromJson(e as Map<String, dynamic>)).toList();
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
                'position': (r['position'] as num?)?.toInt() ?? 0,
              }, conflictAlgorithm: ConflictAlgorithm.replace);
            }
          });
        }
        return data;
      }
      return null;
    } catch (e) {
      debugPrint('CourseService: fetchCourseDetail failed — $e');
      return null;
    }
  }

  Future<bool> enroll(String courseId) async {
    try {
      final resp = await ApiClient.post('/api/courses/$courseId/enroll');
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final db = await DBHelper().database;
        await db.insert('course_progress', {
          'student_id': '',
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
      debugPrint('CourseService: enroll failed — $e');
      return false;
    }
  }

  Future<bool> unenroll(String courseId) async {
    try {
      final resp = await ApiClient.post('/api/courses/$courseId/unenroll');
      if (resp.statusCode == 200) {
        final db = await DBHelper().database;
        await db.delete('course_progress', where: 'course_id = ?', whereArgs: [courseId]);
        _enrolledCourses.removeWhere((e) => e.course.id == courseId);
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('CourseService: unenroll failed — $e');
      return false;
    }
  }

  Future<bool> downloadCourse(String courseId, List<CourseResource> resources) async {
    _downloadProgress.clear();
    final totalBytes = resources.fold<int>(0, (sum, r) => sum + r.fileSize);
    if (!await _hasEnoughStorage(totalBytes)) return false;
    int succeeded = 0;
    for (final resource in resources) {
      final url = '${ApiClient.baseUrl}/files/${resource.filename ?? resource.id}';
      final ext = resource.filename != null ? '.${resource.filename!.split('.').last}' : '';
      final fileName = '${resource.id}$ext';
      try {
        await DownloadQueue().enqueue(
          resource.id, url, fileName,
          title: resource.title,
          onProgress: (received, total) {
            _downloadProgress[resource.id] = total > 0 ? received / total : 0.0;
            notifyListeners();
          },
        );
        succeeded++;
      } catch (e) {
        debugPrint('CourseService: downloadCourse failed for ${resource.id} — $e');
      }
    }
    if (succeeded == resources.length) {
      final db = await DBHelper().database;
      await db.update('course_progress', {
        'total_resources': resources.length,
        'completed_count': resources.length,
      }, where: 'course_id = ?', whereArgs: [courseId]);
    }
    _downloadProgress.clear();
    notifyListeners();
    return succeeded == resources.length;
  }

  Future<bool> syncProgress(String courseId, int currentPosition, int completedCount) async {
    try {
      await ApiClient.dio.put('/api/courses/$courseId/progress', data: {
        'current_position': currentPosition,
        'completed_count': completedCount,
      });
      final db = await DBHelper().database;
      await db.update('course_progress', {
        'current_position': currentPosition,
        'completed_count': completedCount,
        'last_synced': DateTime.now().toIso8601String(),
      }, where: 'course_id = ?', whereArgs: [courseId]);
      return true;
    } catch (e) {
      debugPrint('CourseService: syncProgress failed — $e');
      return false;
    }
  }

  Future<void> submitQuiz(String courseId, String resourceId, Map<String, dynamic> attempt) async {
    await MutationQueue().enqueue(
      '/api/courses/$courseId/quiz/$resourceId/submit',
      method: 'POST',
      body: attempt,
      priority: 'high',
    );
    await _saveQuizAttemptLocally(attempt);
  }

  Future<Map<String, dynamic>?> getCachedCourse(String courseId) async {
    try {
      final db = await DBHelper().database;
      final rows = await db.query('courses', where: 'id = ?', whereArgs: [courseId]);
      if (rows.isEmpty) return null;
      return rows.first;
    } catch (e) {
      debugPrint('CourseService: getCachedCourse failed — $e');
      return null;
    }
  }

  Future<List<Course>> getCachedCatalog() async {
    try {
      final db = await DBHelper().database;
      final rows = await db.query('courses', orderBy: 'synced_at DESC');
      return rows.map((r) {
        return Course(
          id: (r['id'] ?? '').toString(),
          title: (r['title'] ?? '').toString(),
          description: (r['description'] ?? '').toString(),
          subject: (r['subject'] ?? '').toString(),
          grade: (r['grade'] as num?)?.toInt() ?? 0,
          language: (r['language'] ?? 'en').toString(),
          coverImage: (r['cover_image'] ?? '').toString(),
          published: (r['published'] as num?)?.toInt() ?? 0,
          teacherUsername: (r['teacher_username'] ?? '').toString(),
          enrollmentCount: (r['enrollment_count'] as num?)?.toInt() ?? 0,
          createdAt: (r['created_at'] ?? '').toString(),
          updatedAt: (r['updated_at'] ?? '').toString(),
        );
      }).toList();
    } catch (e) {
      debugPrint('CourseService: getCachedCatalog failed — $e');
      return [];
    }
  }

  Future<void> loadEnrolledCourses() async {
    try {
      final db = await DBHelper().database;
      final progressRows = await db.query('course_progress');
      final result = <({Course course, Map<String, dynamic>? progress})>[];
      for (final pRow in progressRows) {
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
      debugPrint('CourseService: loadEnrolledCourses failed — $e');
    }
  }

  Future<int> getCompletedCourseCount() async {
    try {
      final db = await DBHelper().database;
      final result = await db.rawQuery('SELECT COUNT(*) AS cnt FROM course_progress WHERE completed = 1');
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      debugPrint('CourseService: getCompletedCourseCount failed — $e');
      return 0;
    }
  }

  Future<int> getInProgressCount() async {
    try {
      final db = await DBHelper().database;
      final result = await db.rawQuery('SELECT COUNT(*) AS cnt FROM course_progress WHERE completed = 0');
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      debugPrint('CourseService: getInProgressCount failed — $e');
      return 0;
    }
  }

  Future<double> getCourseProgress(String courseId) async {
    try {
      final db = await DBHelper().database;
      final rows = await db.query('course_progress',
        columns: ['completed_count', 'total_resources'],
        where: 'course_id = ?', whereArgs: [courseId],
      );
      if (rows.isEmpty) return 0.0;
      final completed = (rows.first['completed_count'] as num?)?.toInt() ?? 0;
      final total = (rows.first['total_resources'] as num?)?.toInt() ?? 0;
      return total > 0 ? completed / total : 0.0;
    } catch (e) {
      debugPrint('CourseService: getCourseProgress failed — $e');
      return 0.0;
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
