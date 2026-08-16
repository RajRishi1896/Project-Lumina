import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart' show join;
import 'package:sqflite/sqflite.dart';

/// Singleton helper for managing the local SQLite database.
/// Provides CRUD operations for resources, activity, bookmarks, downloads,
/// and pending downloads tables with automatic schema migrations.
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
    return await openDatabase(path, version: 17, onCreate: _createDB, onUpgrade: _onUpgrade);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE resources (
        id TEXT PRIMARY KEY,
        path TEXT UNIQUE,
        title TEXT,
        type TEXT
      );
    ''');

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
      CREATE TABLE IF NOT EXISTS zim_archives_local (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        article_count INTEGER DEFAULT 0,
        language TEXT DEFAULT 'en'
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

  /// Removes the bookmark identified by [resourceId].
  Future<void> removeBookmark(String resourceId) async {
    final db = await database;
    await db.delete('bookmarks', where: 'resource_id = ?', whereArgs: [resourceId]);
  }

  /// A set of all bookmarked resource IDs.
  Future<Set<String>> getBookmarkedIds() async {
    final db = await database;
    final rows = await db.query('bookmarks', columns: ['resource_id']);
    return rows.map((r) => r['resource_id'] as String).toSet();
  }

  /// A list of all bookmarked resources ordered by most recent first.
  Future<List<Map<String, dynamic>>> getBookmarkedResources() async {
    final db = await database;
    return await db.query('bookmarks', orderBy: 'bookmarked_at DESC');
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
  Future<void> removeDownload(String resourceId) async {
    final db = await database;
    await db.delete('downloads', where: 'resource_id = ?', whereArgs: [resourceId]);
  }

  /// A set of all downloaded resource IDs.
  Future<Set<String>> getDownloadedIds() async {
    final db = await database;
    final rows = await db.query('downloads', columns: ['resource_id']);
    return rows.map((r) => r['resource_id'] as String).toSet();
  }

  /// A list of all downloaded resources ordered by most recent first.
  Future<List<Map<String, dynamic>>> getDownloadedResources() async {
    final db = await database;
    return await db.query('downloads', orderBy: 'downloaded_at DESC');
  }

  /// A set of resource IDs whose downloads were removed from the server
  /// catalog (see `server_removed`). The local files remain usable.
  Future<Set<String>> getRemovedDownloadIds() async {
    final db = await database;
    final rows = await db.query('downloads', columns: ['resource_id'], where: 'server_removed = 1');
    return rows.map((r) => r['resource_id'] as String).toSet();
  }

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
  Future<void> removePendingDownload(String resourceId) async {
    final db = await database;
    await db.delete('pending_downloads', where: 'resource_id = ?', whereArgs: [resourceId]);
  }

  /// A set of all pending download resource IDs.
  Future<Set<String>> getPendingIds() async {
    final db = await database;
    final rows = await db.query('pending_downloads', columns: ['resource_id']);
    return rows.map((r) => r['resource_id'] as String).toSet();
  }

  /// A list of all pending downloads ordered by oldest first.
  Future<List<Map<String, dynamic>>> getAllPendingDownloads() async {
    final db = await database;
    return await db.query('pending_downloads', orderBy: 'added_at ASC');
  }

  /// Marks an article as downloaded by setting `is_downloaded = 1`.
  ///
  /// Uses INSERT OR REPLACE so the row exists even when no prior INSERT ever
  /// populated `zim_articles_local` (the table was previously write-only).
  /// The existing title (if any) is preserved.
  Future<void> markZimArticleDownloaded(String articleId) async {
    final db = await database;
    await db.rawInsert(
      'INSERT OR REPLACE INTO zim_articles_local (article_id, title, is_downloaded) '
      'VALUES (?, COALESCE((SELECT title FROM zim_articles_local WHERE article_id = ?), ""), 1)',
      [articleId, articleId],
    );
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

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    for (var v = oldVersion + 1; v <= newVersion; v++) {
      if (v == 2) {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS bookmarks (
            resource_id TEXT PRIMARY KEY,
            title TEXT,
            subject TEXT,
            grade TEXT,
            type TEXT,
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
            downloaded_at INTEGER
          )
        ''');
      }
      if (v <= 3) {
        try {
          await db.execute('ALTER TABLE downloads ADD COLUMN mtime REAL DEFAULT 0');
        } catch (_) { } }
      if (v >= 4) {
        try {
          await db.execute('ALTER TABLE bookmarks ADD COLUMN pdf_url TEXT');
        } catch (_) { } }
      if (v >= 5) {
        try {
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
        } catch (_) { } }
      if (v >= 6) {
        try {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS pending_mutations (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              endpoint TEXT NOT NULL,
              method TEXT NOT NULL DEFAULT 'POST',
              body TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              retries INTEGER NOT NULL DEFAULT 0
            )
          ''');
        } catch (_) { } }
      if (v >= 7) {
        try {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS catalog (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              type TEXT NOT NULL,
              subject TEXT,
              grade TEXT,
              pdf_url TEXT,
              mtime REAL DEFAULT 0,
              synced_at INTEGER NOT NULL
            )
          ''');
        } catch (_) { } }
      if (v >= 8) {
        try {
          await db.execute('ALTER TABLE activity ADD COLUMN subject TEXT');
        } catch (_) { } }
      if (v >= 8) {
        try {
          await db.execute("ALTER TABLE pending_mutations ADD COLUMN priority TEXT NOT NULL DEFAULT 'normal'");
        } catch (_) {}
      }
      if (v >= 10) {
        try { await db.execute('CREATE TABLE IF NOT EXISTS courses (id TEXT PRIMARY KEY, title TEXT NOT NULL, description TEXT DEFAULT \'\', subject TEXT DEFAULT \'\', grade INTEGER DEFAULT 0, language TEXT DEFAULT \'en\', cover_image TEXT DEFAULT \'\', published INTEGER DEFAULT 0, teacher_username TEXT DEFAULT \'\', enrollment_count INTEGER DEFAULT 0, created_at TEXT DEFAULT \'\', updated_at TEXT DEFAULT \'\', synced_at INTEGER NOT NULL DEFAULT 0)'); } catch (_) {}
        try { await db.execute('CREATE TABLE IF NOT EXISTS course_resources (id TEXT PRIMARY KEY, course_id TEXT NOT NULL, resource_type TEXT NOT NULL DEFAULT \'textbook\', title TEXT DEFAULT \'\', original_name TEXT DEFAULT \'\', filename TEXT DEFAULT \'\', file_size INTEGER DEFAULT 0, position INTEGER NOT NULL DEFAULT 0)'); } catch (_) {}
        try { await db.execute('CREATE TABLE IF NOT EXISTS course_progress (student_id TEXT NOT NULL, course_id TEXT NOT NULL, current_position INTEGER DEFAULT 0, completed_count INTEGER DEFAULT 0, total_resources INTEGER DEFAULT 0, completed INTEGER DEFAULT 0, last_synced TEXT DEFAULT \'\', enrolled_at TEXT DEFAULT \'\', PRIMARY KEY (student_id, course_id))'); } catch (_) {}
        try { await db.execute('CREATE TABLE IF NOT EXISTS quiz_attempts (id TEXT PRIMARY KEY, student_id TEXT NOT NULL, course_id TEXT NOT NULL, resource_id TEXT NOT NULL, attempt_number INTEGER NOT NULL DEFAULT 1, score REAL DEFAULT 0.0, passed INTEGER DEFAULT 0, answers_json TEXT DEFAULT \'\', started_at TEXT DEFAULT \'\', submitted_at TEXT DEFAULT \'\', time_taken_seconds INTEGER DEFAULT 0, quiz_version INTEGER DEFAULT 1, threshold_at_submission REAL DEFAULT 0.0, sync_status INTEGER DEFAULT 0)'); } catch (_) {}
        try { await db.execute('CREATE TABLE IF NOT EXISTS similar_courses (course_id TEXT NOT NULL, similar_course_id TEXT NOT NULL, PRIMARY KEY (course_id, similar_course_id))'); } catch (_) {}
        try { await db.execute('CREATE INDEX IF NOT EXISTS idx_cr_course_id ON course_resources(course_id)'); } catch (_) {}
        try { await db.execute('CREATE INDEX IF NOT EXISTS idx_cp_student ON course_progress(student_id)'); } catch (_) {}
        try { await db.execute('CREATE INDEX IF NOT EXISTS idx_qa_student ON quiz_attempts(student_id)'); } catch (_) {}
      }
      if (v >= 11) {
        try { await db.execute('CREATE TABLE IF NOT EXISTS zim_archives_local (id TEXT PRIMARY KEY, title TEXT NOT NULL, article_count INTEGER DEFAULT 0, language TEXT DEFAULT \'en\')'); } catch (_) {}
        try { await db.execute('CREATE TABLE IF NOT EXISTS zim_articles_local (article_id TEXT PRIMARY KEY, title TEXT NOT NULL, archive_id TEXT, has_thumbnail INTEGER DEFAULT 0, is_downloaded INTEGER DEFAULT 0)'); } catch (_) {}
      }
      if (v >= 12) {
        try { await db.execute('CREATE TABLE IF NOT EXISTS quiz_cache (cache_key TEXT PRIMARY KEY, quiz_json TEXT NOT NULL, cached_at INTEGER NOT NULL)'); } catch (_) {}
      }
      if (v >= 13) {
        try { await db.execute('ALTER TABLE zim_articles_local ADD COLUMN path TEXT DEFAULT \'\''); } catch (_) {}
        try { await db.execute('ALTER TABLE zim_articles_local ADD COLUMN namespace TEXT DEFAULT \'A\''); } catch (_) {}
      }
      if (v >= 15) {
        try { await db.execute('ALTER TABLE catalog ADD COLUMN file_size INTEGER DEFAULT 0'); } catch (_) {}
        try { await db.execute('ALTER TABLE catalog ADD COLUMN page_count INTEGER DEFAULT 0'); } catch (_) {}
        try { await db.execute('ALTER TABLE catalog ADD COLUMN duration_seconds INTEGER DEFAULT 0'); } catch (_) {}
        try { await db.execute('ALTER TABLE course_resources ADD COLUMN page_count INTEGER DEFAULT 0'); } catch (_) {}
        try { await db.execute('ALTER TABLE course_resources ADD COLUMN duration_seconds INTEGER DEFAULT 0'); } catch (_) {}
      }
      if (v >= 16) {
        try { await db.execute('CREATE TABLE IF NOT EXISTS flashcard_decks_local (id TEXT PRIMARY KEY, title TEXT NOT NULL, source TEXT NOT NULL DEFAULT \'local\', created_at INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL DEFAULT 0)'); } catch (_) {}
        try { await db.execute('CREATE TABLE IF NOT EXISTS flashcard_cards_local (id TEXT PRIMARY KEY, deck_id TEXT NOT NULL, front TEXT NOT NULL, back TEXT NOT NULL, position INTEGER NOT NULL DEFAULT 0)'); } catch (_) {}
        try { await db.execute('CREATE TABLE IF NOT EXISTS flashcard_reviews_local (card_id TEXT PRIMARY KEY, ease REAL NOT NULL DEFAULT 2.5, interval_days INTEGER NOT NULL DEFAULT 0, due_at INTEGER NOT NULL DEFAULT 0, reviews_count INTEGER NOT NULL DEFAULT 0, last_reviewed_at INTEGER NOT NULL DEFAULT 0)'); } catch (_) {}
        try { await db.execute('CREATE TABLE IF NOT EXISTS flashcard_submissions_local (id TEXT PRIMARY KEY, deck_id TEXT NOT NULL, status TEXT NOT NULL DEFAULT \'pending\', reason TEXT DEFAULT \'\', submitted_at INTEGER NOT NULL DEFAULT 0)'); } catch (_) {}
        try { await db.execute('CREATE INDEX IF NOT EXISTS idx_flash_cards_deck ON flashcard_cards_local(deck_id)'); } catch (_) {}
        try { await db.execute('CREATE INDEX IF NOT EXISTS idx_flash_reviews_due ON flashcard_reviews_local(due_at)'); } catch (_) {}
      }
      if (v >= 17) {
        try { await db.execute('ALTER TABLE downloads ADD COLUMN server_removed INTEGER DEFAULT 0'); } catch (_) {}
      }
    }
  }

}
