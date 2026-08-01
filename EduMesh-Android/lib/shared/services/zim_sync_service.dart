import 'package:flutter/foundation.dart';
import '../../core/models/zim_article_model.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/db_helper.dart';

/// Paginated search/browse result from the server.
class ZimSearchResult {
  final List<ZimArticle> articles;
  final int total;
  final int offset;
  final bool hasMore;

  ZimSearchResult({
    required this.articles,
    required this.total,
    required this.offset,
    required this.hasMore,
  });
}

/// Server-side ZIM search and browse. No full-index sync.
///
/// Uses `/zim/search` for ranked search and `/zim/articles` for alphabetical
/// browsing. Local SQLite only tracks downloaded articles for offline access.
class ZimSyncService {
  static final ZimSyncService instance = ZimSyncService._();
  ZimSyncService._();

  Set<String> _downloadedIds = {};

  Set<String> get downloadedIds => _downloadedIds;

  /// Search ZIM articles on the server with relevance ranking.
  ///
  /// Returns up to [limit] results starting at [offset]. The server handles
  /// FTS5 ranking, case-insensitive matching, and pagination.
  Future<ZimSearchResult> searchOnServer(String query, {
    int offset = 0,
    int limit = 50,
  }) async {
    final resp = await ApiClient.get('/zim/search', queryParameters: {
      'query': query,
      'offset': offset.toString(),
      'limit': limit.toString(),
    }).timeout(const Duration(seconds: 30));

    final data = resp.data;
    if (data is! Map) {
      throw Exception('Search: unexpected response ${resp.statusCode}: ${resp.data.runtimeType}');
    }

    final articlesList = data['articles'] as List? ?? [];
    final articles = articlesList.map((j) {
      final m = Map<String, dynamic>.from(j as Map);
      return ZimArticle(
        articleId: (m['article_id'] ?? '').toString(),
        title: (m['title'] ?? '').toString(),
        archiveId: (m['archive_id'] ?? '').toString(),
        hasThumbnail: m['has_thumbnail'] == true,
      );
    }).toList();

    return ZimSearchResult(
      articles: articles,
      total: data['total'] as int? ?? 0,
      offset: data['offset'] as int? ?? offset,
      hasMore: data['has_more'] as bool? ?? false,
    );
  }

  /// Browse ZIM articles on the server in alphabetical order.
  ///
  /// Returns up to [limit] articles starting at [offset]. Used for
  /// the default Wiki tab view when no search query is entered.
  Future<ZimSearchResult> browseOnServer({
    int offset = 0,
    int limit = 50,
    String archiveId = '',
  }) async {
    final params = <String, dynamic>{
      'offset': offset.toString(),
      'limit': limit.toString(),
    };
    if (archiveId.isNotEmpty) params['archive_id'] = archiveId;

    final resp = await ApiClient.get('/zim/articles', queryParameters: params)
        .timeout(const Duration(seconds: 30));

    final data = resp.data;
    if (data is! Map) {
      throw Exception('Browse: unexpected response ${resp.statusCode}: ${resp.data.runtimeType}');
    }

    final articlesList = data['articles'] as List? ?? [];
    final articles = articlesList.map((j) {
      final m = Map<String, dynamic>.from(j as Map);
      return ZimArticle(
        articleId: (m['article_id'] ?? '').toString(),
        title: (m['title'] ?? '').toString(),
        archiveId: (m['archive_id'] ?? '').toString(),
        hasThumbnail: m['has_thumbnail'] == true,
      );
    }).toList();

    return ZimSearchResult(
      articles: articles,
      total: data['total'] as int? ?? 0,
      offset: data['offset'] as int? ?? offset,
      hasMore: data['has_more'] as bool? ?? false,
    );
  }

  /// Search locally downloaded articles for offline fallback.
  ///
  /// Only searches articles that have been previously downloaded and
  /// stored in `zim_articles_local`. Returns at most 50 results.
  Future<List<ZimArticle>> searchLocal(String query) async {
    if (query.length < 2) return [];
    try {
      final db = DBHelper();
      final rows = await db.searchDownloadedZimArticles(query);
      return rows.map((r) => ZimArticle(
        articleId: r['article_id'] as String? ?? '',
        title: r['title'] as String? ?? '',
        archiveId: r['archive_id'] as String? ?? '',
        hasThumbnail: (r['has_thumbnail'] as int? ?? 0) == 1,
      )).toList();
    } catch (e) {
      debugPrint('ZimSyncService: local search failed: $e');
      return [];
    }
  }

  /// Load downloaded article IDs from local DB. Call on startup.
  Future<void> loadDownloadedIds() async {
    try {
      _downloadedIds = await DBHelper().getDownloadedZimArticleIds();
    } catch (e) {
      debugPrint('ZimSyncService: load downloaded IDs failed: $e');
    }
  }

  /// Marks an article as downloaded in the local DB and in-memory set.
  Future<void> markDownloaded(String articleId) async {
    await DBHelper().markZimArticleDownloaded(articleId);
    _downloadedIds.add(articleId);
  }
}
