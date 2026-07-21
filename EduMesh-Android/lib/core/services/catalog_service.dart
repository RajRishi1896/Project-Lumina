import 'package:flutter/foundation.dart';
import '../models/resource_model.dart';
import '../network/api_client.dart';
import '../storage/db_helper.dart';
import '../utils/file_utils.dart';

/// Singleton service that maintains a local cache of the server's resource
/// catalog so the user can browse and queue downloads even when offline.
///
/// The cache is stored in the local SQLite `catalog` table and refreshed
/// from the server every time connectivity is restored.
class CatalogService {
  static final CatalogService _instance = CatalogService._internal();
  factory CatalogService() => _instance;
  CatalogService._internal();

  /// Fetches the full catalog from the server and replaces the local cache.
  /// Safe to call repeatedly -- replaces the entire `catalog` table.
  Future<void> syncCatalog() async {
    try {
      final resp = await ApiClient.get('/api/catalog')
          .timeout(const Duration(seconds: 15));
      final data = resp.data;
      if (data is! List) return;

      final db = await DBHelper().database;
      await db.transaction((txn) async {
        await txn.delete('catalog');
        for (final item in data) {
          if (item is! Map) continue;
          await txn.insert('catalog', {
            'id': (item['id'] ?? '').toString(),
            'title': (item['title'] ?? '').toString(),
            'type': (item['type'] ?? '').toString(),
            'subject': (item['subject'] ?? '').toString(),
            'grade': (item['grade'] ?? '').toString(),
            'pdf_url': (item['pdfUrl'] ?? '').toString(),
            'mtime': (item['mtime'] as num?)?.toDouble() ?? 0,
            'synced_at': DateTime.now().millisecondsSinceEpoch,
          });
        }
      });
    } catch (e) {
      debugPrint('CatalogService: sync failed -- $e');
    }
  }

  /// Fetches similar-course pairings from the server and replaces local cache.
  Future<void> syncSimilarCourses() async {
    try {
      final resp = await ApiClient.get('/api/courses/similar-courses')
          .timeout(const Duration(seconds: 15));
      final data = resp.data;
      if (data is! List) return;
      final db = await DBHelper().database;
      await db.transaction((txn) async {
        await txn.delete('similar_courses');
        for (final item in data) {
          if (item is! Map) continue;
          await txn.insert('similar_courses', {
            'course_id': (item['course_id'] ?? '').toString(),
            'similar_course_id': (item['similar_course_id'] ?? '').toString(),
          });
        }
      });
    } catch (e) {
      debugPrint('CatalogService: similar-courses sync failed -- $e');
    }
  }

  /// Returns all cached resources as [ResourceModel] instances.
  /// Optionally filtered by [subject], [grade], and/or [type].
  Future<List<ResourceModel>> getCatalog({
    String? subject,
    String? grade,
    String? type,
  }) async {
    final db = await DBHelper().database;
    final where = <String>[];
    final args = <dynamic>[];
    if (subject != null && subject.isNotEmpty) {
      where.add('subject = ?');
      args.add(subject);
    }
    if (grade != null && grade.isNotEmpty) {
      where.add('grade = ?');
      args.add(grade);
    }
    if (type != null && type.isNotEmpty) {
      where.add('type = ?');
      args.add(type);
    }
    final rows = await db.query(
      'catalog',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
    );
    return rows.map(_rowToModel).toList();
  }

  /// Full-text search across title, subject, grade, and type in the cached catalog.
  Future<List<ResourceModel>> searchCatalog(String query) async {
    if (query.trim().isEmpty) return [];
    final db = await DBHelper().database;
    final term = '%${query.trim()}%';
    final rows = await db.query(
      'catalog',
      where: 'title LIKE ? OR subject LIKE ? OR grade LIKE ? OR type LIKE ?',
      whereArgs: [term, term, term, term],
      orderBy: 'title ASC',
    );
    return rows.map(_rowToModel).toList();
  }

  ResourceModel _rowToModel(Map<String, dynamic> row) {
    return ResourceModel(
      id: (row['id'] ?? '').toString(),
      title: (row['title'] ?? '').toString(),
      subject: (row['subject'] ?? '').toString(),
      grade: (row['grade'] ?? '').toString(),
      type: parseResourceType((row['type'] ?? '').toString()),
      pdfUrl: (row['pdf_url'] as String?)?.isNotEmpty == true
          ? row['pdf_url'] as String
          : null,
      mtime: (row['mtime'] as num?)?.toDouble() ?? 0,
    );
  }


}
