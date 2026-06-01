import '../../core/network/api_client.dart';

class ZimApiService {
  ZimApiService();

  Future<List<Map<String, dynamic>>> search(String query,
      {int offset = 0, int limit = 20}) async {
    final response = await ApiClient.get('/zim/search', queryParameters: {
      'q': query,
      'offset': offset.toString(),
      'limit': limit.toString(),
    });
    final data = response.data;
    if (data == null || data is! Map<String, dynamic>) return [];
    final List results = data['results'] as List;
    return results.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> fetchPage(String id) async {
    final response = await ApiClient.get('/zim/page', queryParameters: {
      'id': id,
    });
    final data = response.data;
    if (data == null || data is! Map<String, dynamic>) return {};
    return data;
  }
}
