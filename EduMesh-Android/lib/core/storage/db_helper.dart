import 'dart:async';
import 'package:path/path.dart' show join;
import 'package:sqflite/sqflite.dart';

class DBHelper {
  static final DBHelper instance = DBHelper._init();
  static Database? _database;

  DBHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('lumina.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
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
  }

  Future<int> upsertResource(String path, String title, String type) async {
    final db = await instance.database;
    final res = await db.rawInsert('INSERT OR IGNORE INTO resources(path,title,type) VALUES(?,?,?)', [path, title, type]);
    if (res == 0) {
      final row = await db.query('resources', where: 'path=?', whereArgs: [path]);
      return row.first['id'] as int;
    }
    return res;
  }

  Future<void> insertActivity(int resourceId, String date, int seconds) async {
    final db = await instance.database;
    await db.insert('activity', {'resource_id': resourceId, 'date': date, 'seconds': seconds});
  }

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

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
