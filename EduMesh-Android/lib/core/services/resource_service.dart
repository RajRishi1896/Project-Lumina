
import '../network/api_client.dart';

class ResourceService {
  // Updated to return List<ResourceModel>
  Future<List<ResourceModel>> fetchResources(
    ResourceType type, {
    String? grade,
    String? subject,
  }) async {
    try {
      final response = await ApiClient.get('/resources');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        
        // Updated to map to ResourceModel
        return data
            .map((json) => ResourceModel.fromJson(json))
            .where((resource) {
              bool matchesType = resource.type == type;
              bool matchesGrade = grade == null || resource.grade == grade;
              bool matchesSubject = subject == null || resource.subject == subject;
              
              return matchesType && matchesGrade && matchesSubject;
            })
            .toList();
      }
      return [];
    } catch (e) {
      print('Error fetching resources: $e');
      return [];
    }
  }

  // Updated to return List<ResourceModel>
  Future<List<ResourceModel>> fetchAllResources() async {
    try {
      final response = await ApiClient.get('/resources');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        // Updated to map to ResourceModel
        return data.map((json) => ResourceModel.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching all resources: $e');
      return [];
    }
  }
}