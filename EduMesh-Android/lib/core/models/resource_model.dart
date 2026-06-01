// lib/core/models/resource_model.dart
enum ResourceType { textbook, videos, pyq, notes }

class ResourceModel {
  final String id;
  final String title;
  final String subject;
  final String grade;
  final ResourceType type; 
  final String? pdfUrl;
  bool isDownloaded;

  ResourceModel({
    required this.id,
    required this.title,
    required this.subject,
    required this.grade,
    required this.type,
    this.isDownloaded = false,
    this.pdfUrl,
  });

  factory ResourceModel.fromJson(Map<String, dynamic> json) {
    return ResourceModel(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? '',
      subject: json['subject'] ?? 'General',
      grade: json['grade'] ?? '',
      type: _parseType(json['type']?.toString() ?? ''),
      pdfUrl: json['pdfUrl'],
      isDownloaded: json['isDownloaded'] == true,
    );
  }

  static ResourceType _parseType(String type) {
    switch (type.toLowerCase()) {
      case 'textbook':
        return ResourceType.textbook;
      case 'videos':
      case 'video':
        return ResourceType.videos;
      case 'pyq':
        return ResourceType.pyq;
      default:
        return ResourceType.notes;
    }
  }
}