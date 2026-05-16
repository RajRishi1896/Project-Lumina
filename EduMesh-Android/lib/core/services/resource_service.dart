import '../models/resource_model.dart';
import '../network/api_client.dart';

class ResourceService {
  Future<List<Resource>> fetchResources(ResourceType type) async {
    try {
      final response = await ApiClient.get('/resources');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data
            .map((json) => Resource.fromJson(json))
            .where((resource) => resource.type == type)
            .toList();
      }
      return [];
    } catch (e) {
      print('Error fetching resources: $e');
      return [];
    }
  }

  Future<List<Resource>> fetchAllResources() async {
    try {
      final response = await ApiClient.get('/resources');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((json) => Resource.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching all resources: $e');
      return [];
    }
  }
}
