import 'package:edumesh_android/core/models/resource_model.dart';

class MockDataService {
  // Flag to toggle mock data: 0 = No Dummy Data, 1 = Enable Dummy Data
  static const int demodata = 1;

  // Master runtime state pipeline
  static final List<ResourceModel> _resources = [];

  /// Fetches the live structural data stream across views.
  /// If demodata is 0, it returns an empty list regardless of what's in _resources.
  static List<ResourceModel> getResources() {
    if (demodata == 0) {
      return [];
    }
    return _resources;
  }

  /// Dynamic route to append active files
  static void seedIncomingResources(List<ResourceModel> networkItems) {
    _resources.clear();
    _resources.addAll(networkItems);
  }

  /// Helper to inject dummy data for testing the Saved/Dashboard views
  static void initializeWithDummyData() {
    seedIncomingResources([
      // Textbooks
      ResourceModel(id: "t1", title: "Algebra Basics", subject: "Math", grade: "Grade 10", type: ResourceType.textbook, isDownloaded: true),
      ResourceModel(id: "t2", title: "World History", subject: "History", grade: "Grade 9", type: ResourceType.textbook, isDownloaded: false),
      
      // Videos
      ResourceModel(id: "v1", title: "Organic Chemistry", subject: "Chem", grade: "Grade 12", type: ResourceType.videos, isDownloaded: true),
      ResourceModel(id: "v2", title: "Physics Laws", subject: "Physics", grade: "Grade 11", type: ResourceType.videos, isDownloaded: false),
      
      // PYQs
      ResourceModel(id: "p1", title: "Mock Paper 2026", subject: "Biology", grade: "Grade 11", type: ResourceType.pyq, isDownloaded: true),
      
      // Notes
      ResourceModel(id: "n1", title: "Quick Bio Summary", subject: "Biology", grade: "Grade 11", type: ResourceType.notes, isDownloaded: true),
    ]);
  }
}