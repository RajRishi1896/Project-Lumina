// lib/core/models/resource_model.dart
enum ResourceType { textbook, videos, pyq, notes }

class ResourceModel {
  final String id;
  final String title;
  final String subject;
  final String grade;
  final ResourceType type; 
  bool isDownloaded;

  ResourceModel({
    required this.id,
    required this.title,
    required this.subject,
    required this.grade,
    required this.type,
    this.isDownloaded = false,
  });
}