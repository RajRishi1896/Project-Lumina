import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../models/course.dart';
import '../network/api_client.dart';
import '../storage/db_helper.dart';
import '../utils/profile_scoped_prefs.dart';
import 'bookmark_sync.dart';
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

  List<({Course course, Map<String, dynamic>? progress})> _enrolledCourses = [];

  bool get isLoading => _loading;

  /// The most recent error message, or `null` if no error.
  String? get error => _error;

  /// Courses the current student is enrolled in, with their progress rows.
  List<({Course course, Map<String, dynamic>? progress})> get enrolledCourses => _enrolledCourses;

  /// Fetches the course catalog from the hub, caches it locally, and returns it.
  Future<List<Course>> fetchCatalog() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      // Server paginates ({items, total}, default per_page=20): walk all
      // pages so courses beyond page 1 are visible/enrollable.
      final courses = <Course>[];
      var total = -1;
      var page = 1;
      var sawValidPage = false;
      while (page <= 20) {
        final resp = await ApiClient.get('/api/courses?page=$page&per_page=50');
        final data = resp.data;
        List<dynamic>? items;
        if (data is List) {
          items = data;
        } else if (data is Map && data['items'] is List) {
          items = data['items'] as List;
          total = (data['total'] as num?)?.toInt() ?? -1;
        } else {
          break;
        }
        sawValidPage = true;
        if (items.isEmpty) break;
        courses.addAll(items.map((e) => Course.fromJson(e as Map<String, dynamic>)));
        if ((total >= 0 && courses.length >= total) || items.length < 50) break;
        page++;
      }
      if (!sawValidPage) {
        _loading = false;
        notifyListeners();
        return [];
      }
      final db = await DBHelper().database;
      // ponytail: snapshot versions before overwrite so bumped courses can
      // refresh their detail below without a second read.
      final oldVersions = <String, int>{};
      try {
        final oldRows = await db.query('courses', columns: ['id', 'version']);
        for (final r in oldRows) {
          oldVersions[(r['id'] ?? '').toString()] = (r['version'] as num?)?.toInt() ?? 1;
        }
      } catch (_) {}
      if (courses.isEmpty) {
        // ponytail: an empty 200 is more likely a server glitch than a real
        // wipe; only honour it when the local table is already empty.
        // Mirrors CatalogService.syncCatalog's guard: replacing all courses
        // here would let deleteOrphanedCourseData() purge progress/quiz
        // history unrecoverably.
        final existing = await db.query('courses', columns: ['id'], limit: 1);
        if (existing.isNotEmpty) {
          debugPrint('CourseService: server returned empty course catalog; keeping local cache');
          final cached = await getCachedCatalog();
          _loading = false;
          _error = null;
          notifyListeners();
          return cached;
        }
      }
      // ponytail: one timestamp per sync run; per-row DateTime.now() is wasted allocations
      final syncedAt = DateTime.now().millisecondsSinceEpoch;
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
            'created_at': c.createdAt ?? '',
            'updated_at': c.updatedAt ?? '',
            'version': c.version,
            'synced_at': syncedAt,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
      // Purge progress/quiz/resource rows for courses that vanished server-side.
      await DBHelper().deleteOrphanedCourseData();
      // Auto-update: a higher served version means changed content. Refresh
      // the cached detail so stale quiz rows are dropped and changed
      // downloads re-enqueued (handled inside fetchCourseDetail).
      for (final c in courses) {
        final old = oldVersions[c.id];
        if (old != null && c.version > old) {
          try {
            await fetchCourseDetail(c.id);
          } catch (e) {
            debugPrint('CourseService: auto-refresh failed for ${c.id}; $e');
          }
        }
      }
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
        await _cacheCourseDetail(courseId, data);
        return data;
      }
      return null;
    } catch (e) {
      debugPrint('CourseService: fetchCourseDetail failed; $e');
      return null;
    }
  }

  /// Persists a course detail payload (version, topics, resources) and heals
  /// stale local state: drops quiz_cache rows for bumped quizzes, re-enqueues
  /// changed downloads, and keeps `total_resources` equal to the live count.
  Future<void> _cacheCourseDetail(String courseId, Map<String, dynamic> data) async {
    final db = await DBHelper().database;
    final version = (data['version'] as num?)?.toInt() ?? 1;
    final topicMaps = (data['topics'] is List)
        ? (data['topics'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : const <Map<String, dynamic>>[];
    final resourceMaps = (data['resources'] is List)
        ? (data['resources'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : const <Map<String, dynamic>>[];
    final oldResources = <String, Map<String, dynamic>>{};
    try {
      final rows = await db.query('course_resources',
          columns: ['id', 'file_size', 'updated_at', 'quiz_version'],
          where: 'course_id = ?', whereArgs: [courseId]);
      for (final r in rows) {
        oldResources[(r['id'] ?? '').toString()] = r;
      }
    } catch (_) {}
    // ponytail: an empty 200 with local rows is a glitch, not a wipe; keep
    // local resources/topics and the stored total (completed_count survives,
    // so deleting here zeroes the denominator -> "2/0").
    final keepLocalOnEmpty =
        resourceMaps.isEmpty && topicMaps.isEmpty && oldResources.isNotEmpty;
    if (keepLocalOnEmpty) {
      debugPrint('CourseService: empty detail for $courseId; keeping local resources');
    }
    await db.transaction((txn) async {
      await txn.update('courses', {
        'version': version,
        if (data['updated_at'] != null) 'updated_at': data['updated_at'].toString(),
      }, where: 'id = ?', whereArgs: [courseId]);
      if (keepLocalOnEmpty) return;
      await txn.delete('course_topics', where: 'course_id = ?', whereArgs: [courseId]);
      for (final t in topicMaps) {
        final rawMode = (t['unlock_mode']?.toString() ?? 'all').toLowerCase();
        await txn.insert('course_topics', {
          'course_id': courseId,
          'id': (t['id'] ?? '').toString(),
          'title': (t['title'] ?? '').toString(),
          'position': (t['position'] as num?)?.toInt() ?? 0,
          'unlock_mode': rawMode == 'sequential' ? 'sequential' : 'all',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await txn.delete('course_resources', where: 'course_id = ?', whereArgs: [courseId]);
      for (final r in resourceMaps) {
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
          'topic_id': (r['topic_id'] ?? '').toString(),
          'updated_at': (r['updated_at'] ?? '').toString(),
          'quiz_version': (r['quiz_version'] as num?)?.toInt() ?? 1,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      // completed_count keeps its meaning (rows completed); total tracks live.
      await txn.update('course_progress', {'total_resources': resourceMaps.length},
          where: 'course_id = ?', whereArgs: [courseId]);
    });
    // Prune per-resource completion prefs for resources this version removed
    // (prune here too: the player only prunes on open, and a bumped course
    // may never be reopened before its progress row is read elsewhere).
    // Skipped when local rows were kept on an empty payload: liveIds is empty
    // there and pruning would wipe every saved completion.
    if (!keepLocalOnEmpty) {
      try {
        final liveIds = resourceMaps.map((r) => (r['id'] ?? '').toString()).toSet();
        final saved = await ProfileScopedPrefs.getStringList(courseDonePrefsKey(courseId));
        final pruned = pruneCourseDoneIds(saved, liveIds);
        if (pruned.length != saved.length) {
          await ProfileScopedPrefs.setStringList(courseDonePrefsKey(courseId), pruned);
        }
      } catch (_) {}
    }
    // Drop stale quiz payloads for bumped quizzes so the next open refetches.
    for (final r in resourceMaps) {
      final id = (r['id'] ?? '').toString();
      if (id.isEmpty) continue;
      final isQuiz = (r['resource_type']?.toString() ?? '').toLowerCase() == 'quiz';
      if (!isQuiz) continue;
      final oldQv = (oldResources[id]?['quiz_version'] as num?)?.toInt() ?? 1;
      final newQv = (r['quiz_version'] as num?)?.toInt() ?? 1;
      if (newQv > oldQv) {
        try {
          await DBHelper().removeCachedQuiz('${courseId}_$id');
        } catch (_) {}
      }
    }
    // Re-enqueue previously downloaded files whose bytes changed upstream.
    final changedIds = <String>[];
    for (final r in resourceMaps) {
      final id = (r['id'] ?? '').toString();
      final old = oldResources[id];
      if (old == null || id.isEmpty) continue;
      final sizeChanged = ((r['file_size'] as num?)?.toInt() ?? 0) != ((old['file_size'] as num?)?.toInt() ?? 0);
      final oldUpdated = (old['updated_at'] ?? '').toString();
      final newUpdated = (r['updated_at'] ?? '').toString();
      final timeChanged = oldUpdated.isNotEmpty && newUpdated.isNotEmpty && oldUpdated != newUpdated;
      if (sizeChanged || timeChanged) changedIds.add(id);
    }
    if (changedIds.isNotEmpty) {
      final placeholders = List.filled(changedIds.length, '?').join(',');
      List<Map<String, dynamic>> dlRows = const [];
      try {
        dlRows = await db.query('downloads',
            columns: ['resource_id'], where: 'resource_id IN ($placeholders)', whereArgs: changedIds);
      } catch (_) {}
      final downloaded = dlRows.map((d) => (d['resource_id'] ?? '').toString()).toSet();
      final byId = {for (final r in resourceMaps) (r['id'] ?? '').toString(): r};
      final meta = await _courseMeta(courseId);
      for (final id in downloaded) {
        final r = byId[id];
        if (r == null) continue;
        try {
          await db.delete('downloads', where: 'resource_id = ?', whereArgs: [id]);
          final res = CourseResource.fromJson({...r, 'course_id': courseId});
          final filename = res.filename ?? '';
          final url = filename.contains('/')
              ? '${ApiClient.baseUrl}/files/$filename'
              : '${ApiClient.baseUrl}/files/courses/$courseId/resources/${filename.isEmpty ? id : filename}';
          await DownloadQueue().enqueue(id, url, courseDownloadFileName(res),
              title: res.title,
              subject: meta.subject,
              grade: meta.grade,
              type: courseDownloadType(res.resourceType));
        } catch (e) {
          debugPrint('CourseService: re-enqueue failed for $id; $e');
        }
      }
    }
  }

  /// Returns the locally cached course detail (version, topics, resources)
  /// for offline use, or null when nothing is cached.
  Future<Map<String, dynamic>?> getCachedCourseDetail(String courseId) async {
    try {
      final db = await DBHelper().database;
      final courseRows =
          await db.query('courses', where: 'id = ?', whereArgs: [courseId], limit: 1);
      if (courseRows.isEmpty) return null;
      final topicRows = await db.query('course_topics',
          where: 'course_id = ?', whereArgs: [courseId], orderBy: 'position ASC');
      final resRows = await db.query('course_resources',
          where: 'course_id = ?', whereArgs: [courseId], orderBy: 'position ASC');
      return {
        ...courseRows.first,
        'topics': topicRows
            .map((t) => {
                  'id': t['id'],
                  'title': t['title'],
                  'position': t['position'],
                  'unlock_mode': t['unlock_mode'],
                })
            .toList(),
        'resources': resRows,
      };
    } catch (e) {
      debugPrint('CourseService: getCachedCourseDetail failed; $e');
      return null;
    }
  }

  /// Fetches a standalone quiz, refreshing the cache when the served
  /// `quiz_version` meets or exceeds the cached one. Returns the served
  /// payload when online, else the cached payload (or null).
  Future<Map<String, dynamic>?> fetchStandaloneQuiz(String resourceId) async {
    final cacheKey = '${resourceId}_$resourceId';
    Map<String, dynamic>? cached;
    try {
      cached = await DBHelper().getCachedQuiz(cacheKey);
    } catch (_) {}
    try {
      final resp = await ApiClient.get('/api/quiz-resource/$resourceId');
      if (resp.statusCode == 200 && resp.data is Map) {
        final served = resp.data as Map<String, dynamic>;
        final servedVersion = quizVersionOf(served);
        final cachedVersion = cached == null ? 0 : quizVersionOf(cached);
        if (cached == null || servedVersion >= cachedVersion) {
          try {
            await DBHelper().cacheQuiz(cacheKey, served);
          } catch (_) {}
        }
        return served;
      }
    } catch (e) {
      debugPrint('CourseService: fetchStandaloneQuiz failed; $e');
    }
    return cached;
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
    final meta = await _courseMeta(courseId);
    int succeeded = 0;
    for (final resource in resources) {
      final String url;
      if (resource.filename != null && resource.filename!.contains('/')) {
        url = '${ApiClient.baseUrl}/files/${resource.filename}';
      } else {
        url = '${ApiClient.baseUrl}/files/courses/${resource.courseId}/resources/${resource.filename ?? resource.id}';
      }
      final fileName = courseDownloadFileName(resource);
        try {
          await DownloadQueue().enqueue(
            resource.id, url, fileName,
            title: resource.title,
            subject: meta.subject,
            grade: meta.grade,
            type: courseDownloadType(resource.resourceType),
            groupId: courseId,
            groupTitle: meta.title,
          );
        succeeded++;
      } catch (e) {
        debugPrint('CourseService: downloadCourse failed for ${resource.id}; $e');
      }
    }
    notifyListeners();
    return succeeded == resources.length;
  }

  /// Removes the current student's enrollment in [courseId].
  ///
  /// Issues `DELETE /api/courses/{courseId}/enroll` but tolerates a 404 or an
  /// unreachable hub: local state is cleared regardless. Drops the student's
  /// `course_progress` row, the cached `course_resources` rows, and the
  /// per-resource completion prefs for the course; quiz-attempt history and
  /// the shared `courses` catalog row stay.
  Future<bool> unenroll(String courseId) async {
    try {
      await ApiClient.ensureInitialized();
      await ApiClient.dio.delete('/api/courses/$courseId/enroll');
    } catch (e) {
      debugPrint('CourseService: unenroll server call failed (tolerated); $e');
    }
    try {
      final db = await DBHelper().database;
      final studentId = await _getStudentId();
      await db.delete('course_progress',
          where: 'student_id = ? AND course_id = ?',
          whereArgs: [studentId, courseId]);
      await db.delete('course_resources',
          where: 'course_id = ?', whereArgs: [courseId]);
      await db.delete('course_topics',
          where: 'course_id = ?', whereArgs: [courseId]);
      try {
        await ProfileScopedPrefs.remove(courseDonePrefsKey(courseId));
      } catch (_) {}
      _enrolledCourses.removeWhere((e) => e.course.id == courseId);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('CourseService: unenroll local clear failed; $e');
      return false;
    }
  }

  /// Subject/grade/title of [courseId] from the cached catalog for download rows.
  /// Falls back to display-safe defaults when the course is not cached
  /// (title falls back to [courseId] so group notifications never go blank).
  Future<({String subject, String grade, String title})> _courseMeta(String courseId) async {
    try {
      final db = await DBHelper().database;
      final rows = await db.query('courses',
          columns: ['subject', 'grade', 'title'],
          where: 'id = ?', whereArgs: [courseId], limit: 1);
      if (rows.isNotEmpty) {
        final subject = (rows.first['subject'] ?? '').toString();
        final grade = (rows.first['grade'] ?? '').toString();
        final title = (rows.first['title'] ?? '').toString();
        return (
          subject: subject.isEmpty ? 'General' : subject,
          grade: grade.isEmpty ? 'General' : grade,
          title: title.isEmpty ? courseId : title,
        );
      }
    } catch (_) {}
    return (subject: 'General', grade: 'General', title: courseId);
  }

  /// Submits a quiz attempt via [MutationQueue] for offline support, then
  /// persists locally.
  ///
  /// Returns the server response when the attempt was graded online (the
  /// server-graded row plus per-question `results`), or null when the
  /// submission was queued for a later flush.
  Future<dynamic> submitQuiz(String courseId, String resourceId, Map<String, dynamic> attempt) async {
    final response = await MutationQueue().enqueue(
      '/api/courses/$courseId/quiz/$resourceId/submit',
      method: 'POST',
      body: attempt,
    );
    if (response is Map) {
      final graded = Map<String, dynamic>.from(attempt);
      graded['score'] = response['score'] ?? attempt['score'];
      graded['passed'] = response['passed'] ?? attempt['passed'];
      await _saveQuizAttemptLocally(graded);
    } else {
      await _saveQuizAttemptLocally(attempt);
    }
    return response;
  }

  /// Submits a standalone quiz attempt via [MutationQueue] for offline support,
  /// then persists locally.
  ///
  /// Returns the server response when graded online, or null when queued.
  Future<dynamic> submitStandaloneQuiz(String resourceId, Map<String, dynamic> attempt) async {
    final response = await MutationQueue().enqueue(
      '/api/quiz-resource/$resourceId/submit',
      method: 'POST',
      body: attempt,
    );
    if (response is Map) {
      final graded = Map<String, dynamic>.from(attempt);
      graded['score'] = response['score'] ?? attempt['score'];
      graded['passed'] = response['passed'] ?? attempt['passed'];
      await _saveQuizAttemptLocally(graded);
    } else {
      await _saveQuizAttemptLocally(attempt);
    }
    return response;
  }

  /// Updates the best score for a standalone quiz via [MutationQueue] for offline support.
  Future<void> updateStandaloneBestScore(String resourceId, double score, String attemptId) async {
    await MutationQueue().enqueue(
      '/api/quiz-resource/$resourceId/best-score',
      method: 'POST',
      body: {'score': score, 'attempt_id': attemptId},
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
          return await loadEnrolledCourses(); // recurse with now-populated DB
        }
      }

      // ponytail: one IN(...) lookup instead of a per-row query (N+1)
      final result = <({Course course, Map<String, dynamic>? progress})>[];
      final ids = progressRows
          .map((pRow) => (pRow['course_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toList();
      final coursesById = <String, Map<String, dynamic>>{};
      if (ids.isNotEmpty) {
        final placeholders = List.filled(ids.length, '?').join(',');
        final courseRows =
            await db.query('courses', where: 'id IN ($placeholders)', whereArgs: ids);
        for (final r in courseRows) {
          coursesById[(r['id'] ?? '').toString()] = r;
        }
        // ponytail: heal stale totals in one GROUP BY instead of per-row
        // COUNT queries; patch the in-memory rows too so the UI heals now.
        try {
          final countRows = await db.rawQuery(
              'SELECT course_id, COUNT(*) AS n FROM course_resources WHERE course_id IN ($placeholders) GROUP BY course_id',
              ids);
          final liveById = <String, int>{
            for (final r in countRows)
              (r['course_id'] ?? '').toString(): (r['n'] as num?)?.toInt() ?? 0,
          };
          for (final pRow in progressRows) {
            final cid = (pRow['course_id'] ?? '').toString();
            if (cid.isEmpty) continue;
            final live = liveById[cid] ?? 0;
            final storedTotal = (pRow['total_resources'] as num?)?.toInt() ?? 0;
            final storedDone = (pRow['completed_count'] as num?)?.toInt() ?? 0;
            final healedDone =
                (live > 0 && storedDone > live) ? live : storedDone;
            if (live != storedTotal || healedDone != storedDone) {
              await db.update(
                  'course_progress',
                  {'total_resources': live, 'completed_count': healedDone},
                  where: 'course_id = ? AND student_id = ?',
                  whereArgs: [cid, studentId]);
              pRow['total_resources'] = live;
              pRow['completed_count'] = healedDone;
            }
          }
        } catch (_) {}
      }
      for (final pRow in progressRows) {
        final courseId = (pRow['course_id'] ?? '').toString();
        final row = coursesById[courseId];
        if (row != null) {
          result.add((course: _rowToCourse(row), progress: pRow));
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
      final studentId = await _getStudentId();
      final lastSynced = DateTime.now().toIso8601String();
      final syncedAt = DateTime.now().millisecondsSinceEpoch;
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
            'version': (m['version'] as num?)?.toInt() ?? 1,
            'synced_at': syncedAt,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          await txn.insert('course_progress', {
            'student_id': studentId,
            'course_id': m['course_id'] ?? '',
            'current_position': m['current_position'] ?? 0,
            'completed_count': m['completed_count'] ?? 0,
            'total_resources': m['total_resources'] ?? 0,
            'completed': m['completed'] ?? 0,
            'last_synced': lastSynced,
            'enrolled_at': m['enrolled_at'] ?? '',
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
      // Enrollment-restore converged Saved too: a fresh install may hold
      // server bookmarks that were never downloaded to this phone.
      try {
        await BookmarkSync.convergeAfterLogin();
      } catch (_) {}
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
      // ponytail: grade column is TEXT (default 'General'); rows restored
      // from the server can hold strings, so parse like Course.fromJson
      // instead of casting to num (which threw and emptied the catalog).
      grade: num.tryParse(row['grade']?.toString() ?? '')?.toInt() ?? 0,
      language: (row['language'] ?? 'en').toString(),
      coverImage: (row['cover_image'] ?? '').toString(),
      published: num.tryParse(row['published']?.toString() ?? '')?.toInt() ?? 0,
      teacherUsername: (row['teacher_username'] ?? '').toString(),
      createdAt: (row['created_at'] ?? '').toString(),
      updatedAt: (row['updated_at'] ?? '').toString(),
      version: (row['version'] as num?)?.toInt() ?? 1,
    );
  }
}
