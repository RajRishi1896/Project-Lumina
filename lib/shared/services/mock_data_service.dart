import '../../core/models/resource_model.dart';

class MockDataService {
  static List<Resource> getResources() {
    // Return empty list for production/fresh install
    return [];
  }
}
