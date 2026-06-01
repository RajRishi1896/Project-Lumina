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
      ResourceModel(id: "t1", title: "Algebra Basics", subject: "Math", grade: "Grade 10", type: ResourceType.textbook, isDownloaded: true, pdfUrl: "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf"),
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

  // --- Demo Mode Sample Data Getters ---

  static List<Map<String, dynamic>> getSampleSubjects() {
    return [
      {'name': 'Mathematics', 'symbol': 'M', 'class_name': 'All Classes'},
      {'name': 'Physics', 'symbol': 'Ph', 'class_name': 'All Classes'},
      {'name': 'Chemistry', 'symbol': 'Ch', 'class_name': 'All Classes'},
      {'name': 'Biology', 'symbol': 'Bio', 'class_name': 'All Classes'},
      {'name': 'History', 'symbol': 'H', 'class_name': 'All Classes'},
      {'name': 'English Literature', 'symbol': 'EL', 'class_name': 'All Classes'},
      {'name': 'Computer Science', 'symbol': 'CS', 'class_name': 'All Classes'},
    ];
  }

  static List<Map<String, dynamic>> getSampleResources() {
    return [
      {'id': 101, 'title': 'Algebra Fundamentals', 'subject': 'Mathematics', 'type': 'textbook'},
      {'id': 102, 'title': 'Newtonian Mechanics', 'subject': 'Physics', 'type': 'textbook'},
      {'id': 103, 'title': 'Organic Chemistry Reactions', 'subject': 'Chemistry', 'type': 'videos'},
      {'id': 104, 'title': 'Cell Biology Notes', 'subject': 'Biology', 'type': 'notes'},
      {'id': 105, 'title': 'World War II Overview', 'subject': 'History', 'type': 'textbook'},
      {'id': 106, 'title': 'Macbeth Analysis', 'subject': 'English Literature', 'type': 'notes'},
      {'id': 107, 'title': 'Python Programming Basics', 'subject': 'Computer Science', 'type': 'videos'},
      {'id': 108, 'title': 'Calculus PYQ 2025', 'subject': 'Mathematics', 'type': 'pyq'},
      {'id': 109, 'title': 'Thermodynamics PYQ', 'subject': 'Physics', 'type': 'pyq'},
      {'id': 110, 'title': 'Periodic Table Guide', 'subject': 'Chemistry', 'type': 'textbook'},
      {'id': 111, 'title': 'Genetics Crash Course', 'subject': 'Biology', 'type': 'videos'},
      {'id': 112, 'title': 'Data Structures & Algorithms', 'subject': 'Computer Science', 'type': 'textbook'},
    ];
  }

  static List<Map<String, dynamic>> getSampleScholars() {
    return [
      {'id': 'SCH-001', 'name': 'Alice Johnson', 'reset_required': 0},
      {'id': 'SCH-002', 'name': 'Bob Smith', 'reset_required': 1},
      {'id': 'SCH-003', 'name': 'Charlie Brown', 'reset_required': 0},
      {'id': 'SCH-004', 'name': 'Diana Lee', 'reset_required': 0},
      {'id': 'SCH-005', 'name': 'Ethan Davis', 'reset_required': 1},
      {'id': 'SCH-006', 'name': 'Fiona Martinez', 'reset_required': 0},
      {'id': 'SCH-007', 'name': 'George Wilson', 'reset_required': 0},
      {'id': 'SCH-008', 'name': 'Hannah Taylor', 'reset_required': 0},
    ];
  }

  static List<Map<String, dynamic>> getSampleTeachers() {
    return [
      {'name': 'Dr. Sarah Mitchell', 'username': 'sarah.mitchell', 'department': 'Science', 'reset_required': 0},
      {'name': 'Prof. James Anderson', 'username': 'james.anderson', 'department': 'Mathematics', 'reset_required': 1},
      {'name': 'Ms. Emily Clarke', 'username': 'emily.clarke', 'department': 'English', 'reset_required': 0},
      {'name': 'Mr. Robert Chen', 'username': 'robert.chen', 'department': 'Computer Science', 'reset_required': 0},
    ];
  }

  static List<String> getSampleAuditLog() {
    return [
      '[2026-05-29 10:23:15] admin  CREATE_SUBJECT  "Computer Science"',
      '[2026-05-29 10:24:01] admin  UPLOAD_RESOURCE  "Python Programming Basics" (CS)',
      '[2026-05-29 10:25:44] admin  RESET_STUDENT_PWD  SCH-002 (Bob Smith)',
      '[2026-05-29 10:26:30] admin  DELETE_RESOURCE  id=99 ("Old Textbook")',
      '[2026-05-29 10:27:12] admin  CREATE_TEACHER  "Ms. Emily Clarke" (English)',
      '[2026-05-29 10:28:05] admin  IMPORT_ZIM  "wikipedia_en_science.zim" (82 pages)',
      '[2026-05-29 10:29:33] admin  UPDATE_RETENTION  "30d" → "7d"',
      '[2026-05-29 10:30:00] admin  DOWNLOAD_LOGS  duration=7d',
      '[2026-05-29 10:31:22] admin  DISABLE_DEFAULT_ADMIN  initiated',
      '[2026-05-29 10:32:15] admin  DELETE_STUDENT  SCH-009 (removed)',
    ];
  }
}