import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Service that talks to the backend ZIM endpoints.
///
/// The backend must expose two endpoints:
///   GET /zim/search?q={query}&offset={offset}&limit={limit}
///   GET /zim/page?id={id}
class ZimApiService {
  static const String _defaultBaseUrl = 'https://your.server.com'; // TODO: replace with real URL

  static Future<String> _getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('zim_base_url') ?? _defaultBaseUrl;
  }

  /// Search for article titles.
  /// Returns a list of maps with keys: id, title, snippet.
  static Future<List<Map<String, dynamic>>> search(String query,
      {int offset = 0, int limit = 20}) async {
    final baseUrl = await _getBaseUrl();
    final uri = Uri.parse('$baseUrl/zim/search').replace(queryParameters: {
      'q': query,
      'offset': offset.toString(),
      'limit': limit.toString(),
    });
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('ZIM search failed: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final List results = decoded['results'] as List;
    return results.cast<Map<String, dynamic>>();
  }

  /// Fetch the full HTML of an article by its ZIM id.
  /// Returns a map with keys: id, title, html.
  static Future<Map<String, dynamic>> fetchPage(String id) async {
    final baseUrl = await _getBaseUrl();
    final uri = Uri.parse('$baseUrl/zim/page').replace(queryParameters: {
      'id': id,
    });
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('ZIM fetch failed: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return decoded;
  }

  /// Allows the user (or dev) to override the base URL at runtime.
  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('zim_base_url', url);
  }
}
