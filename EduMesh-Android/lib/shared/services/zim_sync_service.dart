import 'package:flutter/foundation.dart';
import '../../core/models/zim_article_model.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/db_helper.dart';

/// Fetches ZIM articles from the hub and persists them to the local SQLite
/// cache so search works offline. Singleton — use [ZimSyncService.instance].
class ZimSyncService {
  static final ZimSyncService instance = ZimSyncService._();
  ZimSyncService._();

  List<ZimArticle> _articles = [];
  Set<String> _downloadedIds = {};

  List<ZimArticle> get articles => _articles;
  Set<String> get downloadedIds => _downloadedIds;

  /// Fetches articles from `/zim/articles` and upserts them into the local
  /// `zim_articles_local` table. Then loads the local copy into memory.
  Future<void> syncFromHub() async {
    try {
      final resp = await ApiClient.get('/zim/articles', queryParameters: {
        'offset': '0',
        'limit': '500',
      }).timeout(const Duration(seconds: 10));

      if (resp.data is List) {
        final db = DBHelper();
        final batch = <Map<String, dynamic>>[];
        for (final j in resp.data) {
          if (j is Map) {
            final map = Map<String, dynamic>.from(j);
            batch.add({
              'article_id': (map['article_id'] ?? '').toString(),
              'title': (map['title'] ?? '').toString(),
              'archive_id': (map['archive_id'] ?? '').toString(),
              'has_thumbnail': map['has_thumbnail'] == true ? 1 : 0,
            });
          }
        }
        if (batch.isNotEmpty) {
          await db.upsertZimArticlesBatch(batch);
        }
      }
    } catch (e) {
      debugPrint('ZimSyncService: sync failed: $e');
    }
    await _loadFromLocal();
  }

  /// Loads articles and downloaded IDs from the local database into memory.
  Future<void> _loadFromLocal() async {
    try {
      final db = DBHelper();
      final rows = await db.getAllZimArticles();
      _articles = rows.map((r) => ZimArticle(
        articleId: r['article_id'] as String? ?? '',
        title: r['title'] as String? ?? '',
        archiveId: r['archive_id'] as String? ?? '',
        hasThumbnail: (r['has_thumbnail'] as int? ?? 0) == 1,
      )).toList();
      _downloadedIds = await db.getDownloadedZimArticleIds();
    } catch (e) {
      debugPrint('ZimSyncService: load from local failed: $e');
    }
  }

  /// Returns all locally cached articles.
  Future<List<ZimArticle>> getAll() async {
    if (_articles.isEmpty) await _loadFromLocal();
    return _articles;
  }

  /// Marks an article as downloaded in the local DB and in-memory set.
  Future<void> markDownloaded(String articleId) async {
    await DBHelper().markZimArticleDownloaded(articleId);
    _downloadedIds.add(articleId);
  }
}
