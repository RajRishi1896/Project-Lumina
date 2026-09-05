import 'dart:convert';
import 'package:path/path.dart' show join;
import 'package:sqflite/sqflite.dart';

/// Local SQLite storage isolated by active profile.
///
/// Each authenticated profile gets its own database file. This prevents
/// bookmarks, downloads, queues, analytics, quiz caches, and flashcard state
/// from crossing users on shared devices without requiring every query to
/// carry a profile_id predicate.
class DBHelper {
  static final DBHelper instance = DBHelper._init();
  static Map<String, Database> _databases = {};
  static String _activeProfileId = 'anonymous';

  DBHelper._init();
  factory DBHelper() => instance;

  /// Switch the active local database. A stable sanitized profile identifier
  /// is used as part of the filename so multiple users can coexist safely.
  Future<void> switchProfile(String? profileId) async {
    final normalized = (profileId ?? '').trim();
    final next = normalized.isEmpty ? 'anonymous' : normalized;
    if (_activeProfileId == next) return;
    _activeProfileId = next;
    await database;
  }

  /// Closes all cached database handles. Intended for app teardown/tests.
  Future<void> closeAll() async {
    final values = _databases.values.toList();
    _databases = {};
    for (final db in values) {
      try { await db.close(); } catch (_) {}
    }
  }

  Future<Database> get database async {
    final existing = _databases[_activeProfileId];
    if (existing != null && existing.isOpen) return existing;
    final db = await _initDB('lumina_${_safeName(_activeProfileId)}.db');
    _databases[_activeProfileId] = db;
    return db;
  }

  static String _safeName(String raw) {
    final value = raw.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return value.isEmpty ? 'anonymous' : value.substring(0, value.length.clamp(1, 80));
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    final db = await openDatabase(path, version: 17, onCreate: _createDB);
    try { await db.execute('CREATE INDEX IF NOT EXISTS idx_activity_subject ON activity(subject)'); } catch (_) {}
    try {
      final cutoff = DateTime.now().subtract(const Duration(days: 90)).toIso8601String().substring(0, 10);
      await db.delete('activity', where: 'date < ?', whereArgs: [cutoff]);
    } catch (_) {}
    return db;
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''CREATE TABLE activity (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      resource_id TEXT,
      date TEXT,
      subject TEXT,
      seconds INTEGER
    );''');
    await db.execute('''CREATE TABLE IF NOT EXISTS bookmarks (
      resource_id TEXT PRIMARY KEY,
      title TEXT,
      subject TEXT,
      grade TEXT,
      type TEXT,
      pdf_url TEXT,
      bookmarked_at INTEGER
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS downloads (
      resource_id TEXT PRIMARY KEY,
      local_path TEXT,
      title TEXT,
      subject TEXT,
      grade TEXT,
      type TEXT,
      mtime REAL DEFAULT 0,
      downloaded_at INTEGER,
      server_removed INTEGER DEFAULT 0
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS pending_downloads (
      resource_id TEXT PRIMARY KEY,
      url TEXT,
      file_name TEXT,
      title TEXT,
      subject TEXT,
      grade TEXT,
      type TEXT,
      mtime REAL DEFAULT 0,
      added_at INTEGER
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS pending_mutations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      endpoint TEXT NOT NULL,
      method TEXT NOT NULL DEFAULT 'POST',
      body TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      retries INTEGER NOT NULL DEFAULT 0,
      priority TEXT NOT NULL DEFAULT 'normal'
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS catalog (
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
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS courses (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      description TEXT DEFAULT '',
      subject TEXT DEFAULT '',
      grade TEXT DEFAULT 'General',
      language TEXT DEFAULT 'en',
      cover_image TEXT DEFAULT '',
      published INTEGER DEFAULT 0,
      teacher_username TEXT DEFAULT '',
      enrollment_count INTEGER DEFAULT 0,
      created_at TEXT DEFAULT '',
      updated_at TEXT DEFAULT '',
      synced_at INTEGER NOT NULL DEFAULT 0
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS course_resources (
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
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS course_progress (
      student_id TEXT NOT NULL,
      course_id TEXT NOT NULL,
      current_position INTEGER DEFAULT 0,
      completed_count INTEGER DEFAULT 0,
      total_resources INTEGER DEFAULT 0,
      completed INTEGER DEFAULT 0,
      last_synced TEXT DEFAULT '',
      enrolled_at TEXT DEFAULT '',
      PRIMARY KEY (student_id, course_id)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS quiz_attempts (
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
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS similar_courses (
      course_id TEXT NOT NULL,
      similar_course_id TEXT NOT NULL,
      PRIMARY KEY (course_id, similar_course_id)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS zim_articles_local (
      article_id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      archive_id TEXT,
      path TEXT DEFAULT '',
      namespace TEXT DEFAULT 'A',
      has_thumbnail INTEGER DEFAULT 0,
      is_downloaded INTEGER DEFAULT 0
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS quiz_cache (
      cache_key TEXT PRIMARY KEY,
      quiz_json TEXT NOT NULL,
      cached_at INTEGER NOT NULL
    )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_activity_subject ON activity(subject)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cr_course_id ON course_resources(course_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cp_student ON course_progress(student_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_qa_student ON quiz_attempts(student_id)');
    await db.execute('''CREATE TABLE IF NOT EXISTS flashcard_decks_local (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      subject TEXT NOT NULL DEFAULT '',
      source TEXT NOT NULL DEFAULT 'local',
      created_at INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL DEFAULT 0
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS flashcard_cards_local (
      id TEXT PRIMARY KEY,
      deck_id TEXT NOT NULL,
      front TEXT NOT NULL,
      back TEXT NOT NULL,
      position INTEGER NOT NULL DEFAULT 0
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS flashcard_reviews_local (
      card_id TEXT PRIMARY KEY,
      ease REAL NOT NULL DEFAULT 2.5,
      interval_days INTEGER NOT NULL DEFAULT 0,
      due_at INTEGER NOT NULL DEFAULT 0,
      reviews_count INTEGER NOT NULL DEFAULT 0,
      last_reviewed_at INTEGER NOT NULL DEFAULT 0
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS flashcard_submissions_local (
      id TEXT PRIMARY KEY,
      deck_id TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      reason TEXT DEFAULT '',
      submitted_at INTEGER NOT NULL DEFAULT 0
    )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_flash_cards_deck ON flashcard_cards_local(deck_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_flash_reviews_due ON flashcard_reviews_local(due_at)');
  }

  Future<void> deleteOrphanedCourseData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('course_progress', where: 'course_id NOT IN (SELECT id FROM courses)');
      await txn.delete('quiz_attempts', where: 'course_id NOT IN (SELECT id FROM courses)');
      await txn.delete('course_resources', where: 'course_id NOT IN (SELECT id FROM courses)');
    });
  }

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

  Future<Set<String>> _resourceIdSet(String table, {String? where, List<Object?>? whereArgs}) async {
    final db = await database;
    final rows = await db.query(table, columns: ['resource_id'], where: where, whereArgs: whereArgs);
    return rows.map((r) => r['resource_id'] as String).toSet();
  }

  Future<void> _deleteResourceRow(String table, String resourceId) async {
    final db = await database;
    await db.delete(table, where: 'resource_id = ?', whereArgs: [resourceId]);
  }

  Future<void> removeBookmark(String resourceId) => _deleteResourceRow('bookmarks', resourceId);
  Future<Set<String>> getBookmarkedIds() => _resourceIdSet('bookmarks');

  Future<List<Map<String, dynamic>>> getBookmarkedResources() async {
    final db = await database;
    return await db.query('bookmarks', orderBy: 'bookmarked_at DESC');
  }

  Future<Map<String, Map<String, dynamic>>> getCatalogEntries(Set<String> ids) async {
    if (ids.isEmpty) return {};
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.query('catalog', where: 'id IN ($placeholders)', whereArgs: ids.toList());
    return {for (final r in rows) r['id'] as String: r};
  }

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

  Future<void> removeDownload(String resourceId) => _deleteResourceRow('downloads', resourceId);
  Future<Set<String>> getDownloadedIds() => _resourceIdSet('downloads');

  Future<Set<String>> getCourseResourceIds() async {
    final db = await database;
    final rows = await db.query('course_resources', columns: ['id']);
    return rows.map((r) => r['id']?.toString() ?? '').where((id) => id.isNotEmpty).toSet();
  }

  Future<List<Map<String, dynamic>>> getDownloadedResources() async {
    final db = await database;
    return await db.query('downloads', orderBy: 'downloaded_at DESC');
  }

  Future<Map<String, dynamic>?> getDownloadedResource(String resourceId) async {
    final db = await database;
    final rows = await db.query('downloads', where: 'resource_id = ?', whereArgs: [resourceId], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<Set<String>> getRemovedDownloadIds() => _resourceIdSet('downloads', where: 'server_removed = 1');

  Future<void> addPendingDownload(String resourceId, String url, String fileName, {String title = '', String subject = '', String grade = '', String type = '', double mtime = 0}) async {
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

  Future<void> removePendingDownload(String resourceId) => _deleteResourceRow('pending_downloads', resourceId);
  Future<Set<String>> getPendingIds() => _resourceIdSet('pending_downloads');

  Future<List<Map<String, dynamic>>> getAllPendingDownloads() async {
    final db = await database;
    return await db.query('pending_downloads', orderBy: 'added_at ASC');
  }

  Future<void> markZimArticleDownloaded(String articleId, {String title = '', String archiveId = ''}) async {
    final db = await database;
    final updated = await db.update('zim_articles_local', {
      'is_downloaded': 1,
      if (title.isNotEmpty) 'title': title,
      if (archiveId.isNotEmpty) 'archive_id': archiveId,
    }, where: 'article_id = ? AND (archive_id = ? OR archive_id IS NULL OR archive_id = ?)', whereArgs: [articleId, archiveId, '']);
    if (updated == 0) {
      await db.insert('zim_articles_local', {
        'article_id': articleId,
        'title': title,
        'archive_id': archiveId,
        'is_downloaded': 1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> recordQuizDownload(String resourceId, String title, String subject, String grade) async {
    final db = await database;
    await db.insert('downloads', {
      'resource_id': resourceId,
      'local_path': 'quiz_cache',
      'title': title,
      'subject': subject,
      'grade': grade,
      'type': 'quiz',
      'downloaded_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Set<String>> getDownloadedZimArticleIds() async {
    final db = await database;
    final rows = await db.query('zim_articles_local', columns: ['article_id', 'archive_id'], where: 'is_downloaded = 1');
    return rows.map((r) {
      final archive = (r['archive_id'] ?? '').toString();
      final article = (r['article_id'] ?? '').toString();
      return archive.isEmpty ? article : '$archive::$article';
    }).toSet();
  }

  Future<List<Map<String, dynamic>>> getDownloadedZimArticles() async {
    final db = await database;
    final rows = await db.query('zim_articles_local', where: 'is_downloaded = 1');
    return rows.map((r) => {
      'resource_id': 'zim_${r['archive_id'] ?? ''}_${r['article_id']}',
      'title': r['title'] as String? ?? '',
      'subject': 'Wikipedia',
      'type': 'kiwix',
      'local_path': '',
      'is_zim': true,
      'article_id': r['article_id'] as String? ?? '',
      'archive_id': r['archive_id'] as String? ?? '',
    }).toList();
  }

  Future<void> cacheQuiz(String cacheKey, Map<String, dynamic> quizJson) async {
    final db = await database;
    await db.insert('quiz_cache', {'cache_key': cacheKey, 'quiz_json': jsonEncode(quizJson), 'cached_at': DateTime.now().millisecondsSinceEpoch}, conflictAlgorithm: ConflictAlgorithm.replace);
    await db.rawDelete('DELETE FROM quiz_cache WHERE cache_key NOT IN (SELECT cache_key FROM quiz_cache ORDER BY cached_at DESC LIMIT 30)');
  }

  Future<Map<String, dynamic>?> getCachedQuiz(String cacheKey) async {
    final db = await database;
    final rows = await db.query('quiz_cache', where: 'cache_key = ?', whereArgs: [cacheKey]);
    if (rows.isEmpty) return null;
    try { return jsonDecode(rows.first['quiz_json'] as String) as Map<String, dynamic>; } catch (_) { return null; }
  }

  Future<void> removeCachedQuiz(String cacheKey) async {
    final db = await database;
    await db.delete('quiz_cache', where: 'cache_key = ?', whereArgs: [cacheKey]);
  }

  Future<Set<String>> getCachedQuizKeys() async {
    final db = await database;
    final rows = await db.query('quiz_cache', columns: ['cache_key']);
    return rows.map((r) => r['cache_key'] as String).toSet();
  }
}
