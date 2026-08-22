import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart' show join;
import 'package:sqflite/sqflite.dart';

/// Singleton helper for managing the local SQLite database.
///
/// Fresh-install schema only: no upgrade chain. Existing databases from older
/// builds are wiped per repo policy (no live environment).
class DBHelper {
  /// The singleton instance of [DBHelper].
  static final DBHelper instance = DBHelper._init();
  static Database? _database;

  DBHelper._init();

  factory DBHelper() => instance;

  /// The lazily-initialized [Database] instance. Opens or creates the database
  /// on first access and runs any pending schema migrations.
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('lumina.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    final db = await openDatabase(path, version: 17, onCreate: _createDB);
    // ponytail: in-schema additions for existing v17 DBs (no version bump).
    try {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_activity_subject ON activity(subject)');
    } catch (_) {}
    try {
      final cutoff = DateTime.now().subtract(const Duration(days: 90)).toIso8601String().substring(0, 10);
      await db.delete('activity', where: 'date < ?', whereArgs: [cutoff]);
    } catch (_) {}
    return db;
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE activity (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        resource_id TEXT,
        date TEXT,
        subject TEXT,
        seconds INTEGER
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS bookmarks (
        resource_id TEXT PRIMARY KEY,
        title TEXT,
        subject TEXT,
        grade TEXT,
        type TEXT,
        pdf_url TEXT,
        bookmarked_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS downloads (
        resource_id TEXT PRIMARY KEY,
        local_path TEXT,
        title TEXT,
        subject TEXT,
        grade TEXT,
        type TEXT,
        mtime REAL DEFAULT 0,
        downloaded_at INTEGER,
        server_removed INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_downloads (
        resource_id TEXT PRIMARY KEY,
        url TEXT,
        file_name TEXT,
        title TEXT,
        subject TEXT,
        grade TEXT,
        type TEXT,
        mtime REAL DEFAULT 0,
        added_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_mutations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        endpoint TEXT NOT NULL,
        method TEXT NOT NULL DEFAULT 'POST',
        body TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        retries INTEGER NOT NULL DEFAULT 0,
        priority TEXT NOT NULL DEFAULT 'normal'
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS catalog (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        type TEXT NOT NULL,
        subject TEXT,
        grade TEXT,
        pdf_url TEXT,
        mtime REAL DEFAULT 0,
        file_size INTEGER DEFAULT 0,
        page_count INTEGER DEFAULT 0,
        duration_seconds INTEGER DEFAULT 0,
        synced_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS courses (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT DEFAULT '',
        subject TEXT DEFAULT '',
        grade INTEGER DEFAULT 0,
        language TEXT DEFAULT 'en',
        cover_image TEXT DEFAULT '',
        published INTEGER DEFAULT 0,
        teacher_username TEXT DEFAULT '',
        enrollment_count INTEGER DEFAULT 0,
        created_at TEXT DEFAULT '',
        updated_at TEXT DEFAULT '',
        synced_at INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS course_resources (
        id TEXT PRIMARY KEY,
        course_id TEXT NOT NULL,
        resource_type TEXT NOT NULL DEFAULT 'textbook',
        title TEXT DEFAULT '',
        original_name TEXT DEFAULT '',
        filename TEXT DEFAULT '',
        file_size INTEGER DEFAULT 0,
        page_count INTEGER DEFAULT 0,
        duration_seconds INTEGER DEFAULT 0,
        position INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS course_progress (
        student_id TEXT NOT NULL,
        course_id TEXT NOT NULL,
        current_position INTEGER DEFAULT 0,
        completed_count INTEGER DEFAULT 0,
        total_resources INTEGER DEFAULT 0,
        completed INTEGER DEFAULT 0,
        last_synced TEXT DEFAULT '',
        enrolled_at TEXT DEFAULT '',
        PRIMARY KEY (student_id, course_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS quiz_attempts (
        id TEXT PRIMARY KEY,
        student_id TEXT NOT NULL,
        course_id TEXT NOT NULL,
        resource_id TEXT NOT NULL,
        attempt_number INTEGER NOT NULL DEFAULT 1,
        score REAL DEFAULT 0.0,
        passed INTEGER DEFAULT 0,
        answers_json TEXT DEFAULT '',
        started_at TEXT DEFAULT '',
        submitted_at TEXT DEFAULT '',
        time_taken_seconds INTEGER DEFAULT 0,
        quiz_version INTEGER DEFAULT 1,
        threshold_at_submission REAL DEFAULT 0.0,
        sync_status INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS similar_courses (
        course_id TEXT NOT NULL,
        similar_course_id TEXT NOT NULL,
        PRIMARY KEY (course_id, similar_course_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS zim_articles_local (
        article_id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        archive_id TEXT,
        path TEXT DEFAULT '',
        namespace TEXT DEFAULT 'A',
        has_thumbnail INTEGER DEFAULT 0,
        is_downloaded INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS quiz_cache (
        cache_key TEXT PRIMARY KEY,
        quiz_json TEXT NOT NULL,
        cached_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_activity_subject ON activity(subject)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_cr_course_id ON course_resources(course_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_cp_student ON course_progress(student_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_qa_student ON quiz_attempts(student_id)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS flashcard_decks_local (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        subject TEXT NOT NULL DEFAULT '',
        source TEXT NOT NULL DEFAULT 'local',
        created_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS flashcard_cards_local (
        id TEXT PRIMARY KEY,
        deck_id TEXT NOT NULL,
        front TEXT NOT NULL,
        back TEXT NOT NULL,
        position INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS flashcard_reviews_local (
        card_id TEXT PRIMARY KEY,
        ease REAL NOT NULL DEFAULT 2.5,
        interval_days INTEGER NOT NULL DEFAULT 0,
        due_at INTEGER NOT NULL DEFAULT 0,
        reviews_count INTEGER NOT NULL DEFAULT 0,
        last_reviewed_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS flashcard_submissions_local (
        id TEXT PRIMARY KEY,
        deck_id TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        reason TEXT DEFAULT '',
        submitted_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_flash_cards_deck ON flashcard_cards_local(deck_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_flash_reviews_due ON flashcard_reviews_local(due_at)
    ''');
  }

  /// Deletes course progress, quiz attempts, and cached course resources
  /// whose parent course no longer exists in the local `courses` table.
  ///
  /// Call after replacing the courses table wholesale (e.g. catalog sync)
  /// so removed courses do not leave orphaned rows forever.
  Future<void> deleteOrphanedCourseData() async {
    final db = await database;
    await db.delete('course_progress', where: 'course_id NOT IN (SELECT id FROM courses)');
    await db.delete('quiz_attempts', where: 'course_id NOT IN (SELECT id FROM courses)');
    await db.delete('course_resources', where: 'course_id NOT IN (SELECT id FROM courses)');
  }

  /// Inserts or replaces a bookmark for the given [resourceId] with its metadata.
  Future<void> upsertBookmark(String resourceId, String title, String subject, String grade, String type, {String? pdfUrl}) async {
    final db = await database;
    await db.insert('bookmarks', {
      'resource_id': resourceId,
      'title': title,
      'subject': subject,
      'grade': grade,
      'type': type,
      'pdf_url': pdfUrl,
      'bookmarked_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// The set of `resource_id` values in [table], optionally filtered.
  Future<Set<String>> _resourceIdSet(String table, {String? where, List<Object?>? whereArgs}) async {
    final db = await database;
    final rows = await db.query(table, columns: ['resource_id'], where: where, whereArgs: whereArgs);
    return rows.map((r) => r['resource_id'] as String).toSet();
  }

  /// Deletes the row keyed by [resourceId] from [table].
  Future<void> _deleteResourceRow(String table, String resourceId) async {
    final db = await database;
    await db.delete(table, where: 'resource_id = ?', whereArgs: [resourceId]);
  }

  /// Removes the bookmark identified by [resourceId].
  Future<void> removeBookmark(String resourceId) => _deleteResourceRow('bookmarks', resourceId);

  /// A set of all bookmarked resource IDs.
  Future<Set<String>> getBookmarkedIds() => _resourceIdSet('bookmarks');

  /// A list of all bookmarked resources ordered by most recent first.
  Future<List<Map<String, dynamic>>> getBookmarkedResources() async {
    final db = await database;
    return await db.query('bookmarks', orderBy: 'bookmarked_at DESC');
  }

  /// Looks up catalog metadata (title/subject/grade/type) for [ids].
  ///
  /// Returns a map keyed by resource ID; missing IDs are simply absent.
  Future<Map<String, Map<String, dynamic>>> getCatalogEntries(Set<String> ids) async {
    if (ids.isEmpty) return {};
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.query(
      'catalog',
      where: 'id IN ($placeholders)',
      whereArgs: ids.toList(),
    );
    return {for (final r in rows) r['id'] as String: r};
  }

  /// Inserts or replaces a download record for the given [resourceId] with its metadata.
  Future<void> insertDownload(String resourceId, String localPath, String title, String subject, String grade, String type, {double mtime = 0}) async {
    final db = await database;
    await db.insert('downloads', {
      'resource_id': resourceId,
      'local_path': localPath,
      'title': title,
      'subject': subject,
      'grade': grade,
      'type': type,
      'mtime': mtime,
      'downloaded_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Removes the download record identified by [resourceId].
  Future<void> removeDownload(String resourceId) => _deleteResourceRow('downloads', resourceId);

  /// A set of all downloaded resource IDs.
  Future<Set<String>> getDownloadedIds() => _resourceIdSet('downloads');

  /// A list of all downloaded resources ordered by most recent first.
  Future<List<Map<String, dynamic>>> getDownloadedResources() async {
    final db = await database;
    return await db.query('downloads', orderBy: 'downloaded_at DESC');
  }

  /// A single downloaded resource by ID, or `null` if not downloaded.
  Future<Map<String, dynamic>?> getDownloadedResource(String resourceId) async {
    final db = await database;
    final rows = await db.query(
      'downloads',
      where: 'resource_id = ?',
      whereArgs: [resourceId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// A set of resource IDs whose downloads were removed from the server
  /// catalog (see `server_removed`). The local files remain usable.
  Future<Set<String>> getRemovedDownloadIds() => _resourceIdSet('downloads', where: 'server_removed = 1');

  /// Adds a download to the pending queue for processing when connectivity is restored.
  Future<void> addPendingDownload(String resourceId, String url, String fileName, {
    String title = '',
    String subject = '',
    String grade = '',
    String type = '',
    double mtime = 0,
  }) async {
    final db = await database;
    await db.insert('pending_downloads', {
      'resource_id': resourceId,
      'url': url,
      'file_name': fileName,
      'title': title,
      'subject': subject,
      'grade': grade,
      'type': type,
      'mtime': mtime,
      'added_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Removes the pending download identified by [resourceId].
  Future<void> removePendingDownload(String resourceId) => _deleteResourceRow('pending_downloads', resourceId);

  /// A set of all pending download resource IDs.
  Future<Set<String>> getPendingIds() => _resourceIdSet('pending_downloads');

  /// A list of all pending downloads ordered by oldest first.
  Future<List<Map<String, dynamic>>> getAllPendingDownloads() async {
    final db = await database;
    return await db.query('pending_downloads', orderBy: 'added_at ASC');
  }

  /// Marks an article as downloaded by setting `is_downloaded = 1`.
  ///
  /// Updates in place so archive_id/path/namespace/has_thumbnail survive.
  /// If no row exists yet, inserts a minimal one (INSERT OR IGNORE guards
  /// against a concurrent insert).
  Future<void> markZimArticleDownloaded(String articleId) async {
    final db = await database;
    final updated = await db.update(
      'zim_articles_local',
      {'is_downloaded': 1},
      where: 'article_id = ?',
      whereArgs: [articleId],
    );
    if (updated == 0) {
      await db.insert('zim_articles_local', {
        'article_id': articleId,
        'title': '',
        'is_downloaded': 1,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  /// Returns the IDs of all ZIM articles that have been downloaded locally.
  Future<Set<String>> getDownloadedZimArticleIds() async {
    final db = await database;
    final rows = await db.query('zim_articles_local',
        columns: ['article_id'], where: 'is_downloaded = 1');
    return rows.map((r) => r['article_id'] as String).toSet();
  }

  /// Returns locally stored ZIM articles so the offline library renders
  /// without needing the hub.
  Future<List<Map<String, dynamic>>> getDownloadedZimArticles() async {
    final db = await database;
    final rows = await db.query(
      'zim_articles_local',
      where: 'is_downloaded = 1',
    );
    return rows.map((r) => {
      'resource_id': 'zim_${r['article_id']}',
      'title': r['title'] as String? ?? '',
      'subject': 'Wikipedia',
      'type': 'kiwix',
      'local_path': '',
      'is_zim': true,
      'article_id': r['article_id'] as String? ?? '',
      'archive_id': r['archive_id'] as String? ?? '',
    }).toList();
  }

  /// Caches a quiz JSON response for offline access. [cacheKey] = "courseId_quizId".
  Future<void> cacheQuiz(String cacheKey, Map<String, dynamic> quizJson) async {
    final db = await database;
    await db.insert('quiz_cache', {
      'cache_key': cacheKey,
      'quiz_json': jsonEncode(quizJson),
      'cached_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    // Cap the view-time quiz cache: keep the 30 most recently viewed quizzes.
    await db.rawDelete('DELETE FROM quiz_cache WHERE cache_key NOT IN '
        '(SELECT cache_key FROM quiz_cache ORDER BY cached_at DESC LIMIT 30)');
  }

  /// Returns the cached quiz JSON for [cacheKey], or null if not cached.
  Future<Map<String, dynamic>?> getCachedQuiz(String cacheKey) async {
    final db = await database;
    final rows = await db.query('quiz_cache', where: 'cache_key = ?', whereArgs: [cacheKey]);
    if (rows.isEmpty) return null;
    try {
      return jsonDecode(rows.first['quiz_json'] as String) as Map<String, dynamic>;
    } catch (_) { return null; }
  }
}

