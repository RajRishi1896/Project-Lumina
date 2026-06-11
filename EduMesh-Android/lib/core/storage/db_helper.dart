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
    return await openDatabase(path, version: 7, onCreate: _createDB, onUpgrade: _onUpgrade);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE resources (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        path TEXT UNIQUE,
        title TEXT,
        type TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE activity (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        resource_id INTEGER,
        date TEXT,
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
        retries INTEGER NOT NULL DEFAULT 0
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
  }

  /// Inserts or ignores a resource record with the given [path], [title], and [type].
  /// Returns the [id] of the existing or newly-inserted row.
  Future<int> upsertResource(String path, String title, String type) async {
    final db = await instance.database;
    final res = await db.rawInsert('INSERT OR IGNORE INTO resources(path,title,type) VALUES(?,?,?)', [path, title, type]);
    if (res == 0) {
      final row = await db.query('resources', where: 'path=?', whereArgs: [path]);
      return row.first['id'] as int;
    }
    return res;
  }

  /// Records an activity entry for the given [resourceId], [date], and [seconds].
  Future<void> insertActivity(int resourceId, String date, int seconds) async {
    final db = await instance.database;
    await db.insert('activity', {'resource_id': resourceId, 'date': date, 'seconds': seconds});
  }

  /// A map of date strings to total seconds of activity for the last [days] days.
  Future<Map<String,int>> getActivityTotalsForLastDays(int days) async {
    final db = await instance.database;
    final now = DateTime.now();
    final start = now.subtract(Duration(days: days-1));
    final rows = await db.rawQuery('''
      SELECT date, SUM(seconds) as total FROM activity
      WHERE date >= ?
      GROUP BY date ORDER BY date ASC
    ''', [start.toIso8601String().split('T')[0]]);
    final Map<String,int> map = {};
    for (final r in rows) {
      map[r['date'] as String] = (r['total'] as int);
    }
    return map;
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
          await db.execute("ALTER TABLE downloads ADD COLUMN mtime REAL DEFAULT 0");
        } catch (_) { } }
      if (v >= 4) {
        try {
          await db.execute("ALTER TABLE bookmarks ADD COLUMN pdf_url TEXT");
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
    }
  }

  /// Closes the database connection. The database will be re-opened on the next access.
  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
