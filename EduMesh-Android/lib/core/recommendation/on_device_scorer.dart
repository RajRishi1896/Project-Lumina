import '../models/course.dart';
import '../storage/db_helper.dart';

/// Offline recommendation engine that scores courses by cluster affinity, grade match, and recency.
///
/// Uses study-time data from the local activity table to rank subject clusters,
/// then scores unenrolled published courses against that ranking.
class OnDeviceScorer {
  static final Map<String, List<String>> _clusters = {
    'science': ['phy', 'chem', 'bio', 'sci'],
    'math': ['math', 'cs'],
    'social': ['soc', 'his', 'geo', 'civ'],
    'commerce': ['com', 'eco'],
    'languages': ['eng', 'hin', 'kan'],
    'general': ['gen'],
  };

  /// Returns the content cluster name for a given [subject] code.
  static String clusterOf(String subject) {
    for (final entry in _clusters.entries) {
      if (entry.value.contains(subject.toLowerCase())) return entry.key;
    }
    return 'general';
  }

  /// Scores all unenrolled published courses and returns them sorted by relevance.
  static Future<List<(Course, double)>> recommend(
      String studentId, String grade) async {
    final db = await DBHelper.instance.database;

    // 1. Activity: rank clusters by total study time
    final activityRows = await db.rawQuery(
        'SELECT subject, SUM(seconds) as total FROM activity WHERE subject IS NOT NULL AND seconds >= 30 GROUP BY subject');

    final clusterSeconds = <String, int>{};
    for (final row in activityRows) {
      final subject = row['subject'] as String?;
      final total = (row['total'] as num?)?.toInt() ?? 0;
      if (subject != null && total > 0) {
        final cluster = clusterOf(subject);
        clusterSeconds[cluster] = (clusterSeconds[cluster] ?? 0) + total;
      }
    }

    final sortedClusters = clusterSeconds.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final rankMap = <String, int>{};
    for (var i = 0; i < sortedClusters.length; i++) {
      rankMap[sortedClusters[i].key] = i;
    }

    // 2. Enrolled and completed courses
    final progressRows = await db.query('course_progress',
        where: 'student_id = ?', whereArgs: [studentId]);

    final enrolledIds = <String>{};
    final completedIds = <String>{};
    for (final row in progressRows) {
      final cid = row['course_id'] as String?;
      if (cid != null) {
        enrolledIds.add(cid);
        if ((row['completed'] as int?) == 1) completedIds.add(cid);
      }
    }

    // 3. Similar course pool from completed courses
    final similarRows = await db.query('similar_courses');
    final similarPool = <String>{};
    for (final row in similarRows) {
      final src = row['course_id'] as String?;
      final dst = row['similar_course_id'] as String?;
      if (src != null && dst != null && completedIds.contains(src)) {
        similarPool.add(dst);
      }
    }

    // 4. All courses
    final courseRows = await db.query('courses');
    final courses = courseRows.map((r) => Course.fromJson(r)).toList();

    // 5. Score unenrolled published courses
    final now = DateTime.now();
    final scored = <(Course, double)>[];

    for (final c in courses) {
      if (c.published != 1) continue;
      if (enrolledIds.contains(c.id)) continue;

      double s = 0;

      // Cluster bonus
      final cl = clusterOf(c.subject);
      if (rankMap.containsKey(cl)) {
        final r = rankMap[cl]!;
        if (r == 0) {
          s += 2;
        } else if (r == 1) {
          s += 1;
        }
      }

      // Grade match
      if (c.grade.toString() == grade) {
        s += 3;
      } else if ((c.grade - int.parse(grade)).abs() <= 1) {
        s += 1;
      }

      // Recency
      final days = _computeDaysSincePublished(c, now);
      if (days >= 0) {
        if (days < 7) {
          s += 2;
        } else if (days < 30) {
          s += 1;
        }
      }

      // Similar boost
      if (similarPool.contains(c.id)) s += 1;

      scored.add((c, s));
    }

    // 6. Sort by score DESC, then publishedAt DESC
    scored.sort((a, b) {
      final cmp = b.$2.compareTo(a.$2);
      if (cmp != 0) return cmp;
      final ta = a.$1.createdAt ?? '';
      final tb = b.$1.createdAt ?? '';
      return tb.compareTo(ta);
    });

    return scored;
  }

  /// Returns the top [limit] recommended courses the student has not yet enrolled in.
  static Future<List<Course>> getRecommendedCourses(
      String studentId, String grade,
      {int limit = 8}) async {
    final scored = await recommend(studentId, grade);
    return scored.take(limit).map((e) => e.$1).toList();
  }

  /// Returns the number of days since [c] was published, or -1 if the date is unparseable.
  static int _computeDaysSincePublished(Course c, [DateTime? now]) {
    final ts = c.createdAt ?? c.updatedAt;
    if (ts == null || ts.isEmpty) return -1;
    final dt = DateTime.tryParse(ts);
    if (dt == null) return -1;
    return (now ?? DateTime.now()).difference(dt).inDays;
  }
}
