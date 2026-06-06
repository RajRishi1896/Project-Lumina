import '../../core/network/api_client.dart';

/// Service that provides access to ZIM article content from the Lumina hub.
///
/// All requests are routed through [ApiClient] to the server's `/zim/`
/// endpoints for listing, searching, and fetching articles.
class ZimApiService {
  ZimApiService();

  /// A paginated list of articles from the loaded ZIM file.
  ///
  /// [offset] and [limit] control pagination. Each entry is a map with keys
  /// such as `id`, `title`, and `snippet`.
  Future<List<Map<String, dynamic>>> listArticles({int offset = 0, int limit = 20}) async {
    final response = await ApiClient.get('/zim/articles', queryParameters: {
      'offset': offset.toString(),
      'limit': limit.toString(),
    });
    final data = response.data;
    if (data == null || data is! List) return [];
    return data.cast<Map<String, dynamic>>();
  }

  /// Searches articles by [query] with pagination support.
  ///
  /// [offset] and [limit] control pagination. Returns a list of result maps,
  /// each containing `id`, `title`, and `snippet`.
  Future<List<Map<String, dynamic>>> search(String query,
      {int offset = 0, int limit = 20}) async {
    final response = await ApiClient.get('/zim/search', queryParameters: {
      'query': query,
      'offset': offset.toString(),
      'limit': limit.toString(),
    });
    final data = response.data;
    if (data == null || data is! Map<String, dynamic>) return [];
    final List results = data['results'] as List;
    return results.cast<Map<String, dynamic>>();
  }

  /// Fetches the full details of a single article by [id].
  ///
  /// Returns a map with keys such as `id`, `title`, and `html_content`.
  Future<Map<String, dynamic>> fetchPage(String id) async {
    final response = await ApiClient.get('/zim/page', queryParameters: {
      'article_id': id,
    });
    final data = response.data;
    if (data == null || data is! Map<String, dynamic>) return {};
    return data;
  }
}
