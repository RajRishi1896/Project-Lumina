import 'dart:async';
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
    return await openDatabase(path, version: 12, onCreate: _createDB, onUpgrade: _onUpgrade);
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
        downloaded_at INTEGER
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
        has_thumbnail INTEGER DEFAULT 0,
        is_downloaded INTEGER DEFAULT 0
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

  /// Removes every entry from the pending downloads queue.
  Future<void> clearAllPendingDownloads() async {
    final db = await database;
    await db.delete('pending_downloads');
  }

  /// Inserts or replaces a ZIM article record in the local database.
  Future<void> upsertZimArticle(String articleId, String title, String archiveId, {bool hasThumbnail = false}) async {
    final db = await database;
    await db.insert('zim_articles_local', {
      'article_id': articleId,
      'title': title,
      'archive_id': archiveId,
      'has_thumbnail': hasThumbnail ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Batch-inserts ZIM articles in a single transaction for efficiency.
  Future<void> upsertZimArticlesBatch(List<Map<String, dynamic>> articles) async {
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final a in articles) {
        batch.insert('zim_articles_local', a, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  /// Returns all stored ZIM article records.
  Future<List<Map<String, dynamic>>> getAllZimArticles() async {
    final db = await database;
    return await db.query('zim_articles_local');
  }

  /// Marks an article as downloaded by setting `is_downloaded = 1`.
  Future<void> markZimArticleDownloaded(String articleId) async {
    final db = await database;
    await db.update('zim_articles_local', {'is_downloaded': 1},
        where: 'article_id = ?', whereArgs: [articleId]);
  }

  /// Returns the IDs of all ZIM articles that have been downloaded locally.
  Future<Set<String>> getDownloadedZimArticleIds() async {
    final db = await database;
    final rows = await db.query('zim_articles_local',
        columns: ['article_id'], where: 'is_downloaded = 1');
    return rows.map((r) => r['article_id'] as String).toSet();
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
      if (v == 12) {
        try {
          await db.execute('DROP TABLE IF EXISTS resources');
          await db.execute('''
            CREATE TABLE resources (
              id TEXT PRIMARY KEY,
              path TEXT UNIQUE,
              title TEXT,
              type TEXT
            )
          ''');
        } catch (_) {}
        try {
          await db.execute('DROP TABLE IF EXISTS activity');
          await db.execute('''
            CREATE TABLE activity (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              resource_id TEXT,
              date TEXT,
              subject TEXT,
              seconds INTEGER
            )
          ''');
        } catch (_) {}
      }
    }
  }

}
