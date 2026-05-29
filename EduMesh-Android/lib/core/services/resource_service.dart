import '../models/resource_model.dart';
import '../network/api_client.dart';

class ResourceService {
  Future<List<ResourceModel>> fetchResources(
    ResourceType type, {
    String? grade,
    String? subject,
  }) async {
    try {
      final response = await ApiClient.get('/resources');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data
            .map((json) => ResourceModel.fromJson(json as Map<String, dynamic>))
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
      return [];
    }
  }

  Future<List<ResourceModel>> fetchAllResources() async {
    try {
      final response = await ApiClient.get('/resources');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data
            .map((json) => ResourceModel.fromJson(json as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}
