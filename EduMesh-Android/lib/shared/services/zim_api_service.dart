import '../network/api_client.dart';

class ZimApiService {
  final ApiClient _apiClient;
  String _baseUrl = 'https://your.server.com';

  ZimApiService(this._apiClient);

  void setBaseUrl(String url) {
    _baseUrl = url;
  }

  Future<List<Map<String, dynamic>>> search(String query,
      {int offset = 0, int limit = 20}) async {
    final response = await _apiClient.get('/zim/search', queryParameters: {
      'q': query,
      'offset': offset.toString(),
      'limit': limit.toString(),
    });
    final decoded = response.data as Map<String, dynamic>;
    final List results = decoded['results'] as List;
    return results.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> fetchPage(String id) async {
    final response = await _apiClient.get('/zim/page', queryParameters: {
      'id': id,
    });
    final decoded = response.data as Map<String, dynamic>;
    return decoded;
  }
}
