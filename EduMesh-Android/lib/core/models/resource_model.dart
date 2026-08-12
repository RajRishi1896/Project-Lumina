import '../utils/file_utils.dart';

/// The category of a learning resource.
enum ResourceType {
  /// Textbooks and reference books.
  textbook,
  /// Video lectures and recordings.
  videos,
  /// Previous year question papers.
  pyq,
  /// Past examination papers.
  pastPaper,
  /// Kiwix offline content (ZIM files).
  kiwix,
  /// Interactive quizzes.
  quiz,
  /// Teacher-created notes and study materials.
  notes,
}

/// The fallback subject used when a resource has no subject assigned.
const String kFallbackSubject = 'General';

/// A model representing a learning resource with its metadata and download status.
class ResourceModel {
  /// The unique identifier for this resource.
  final String id;

  /// The display title of the resource.
  final String title;

  /// The subject category this resource belongs to.
  final String subject;

  /// The grade or class level for this resource.
  final String grade;

  /// The type category of this resource.
  final ResourceType type;

  /// An optional URL to a PDF version of this resource.
  final String? pdfUrl;

  /// The last-modified timestamp of the source file.
  final double mtime;

  /// Whether this resource has been downloaded to the device.
  bool isDownloaded;

  /// The topic name assigned to this resource (e.g. "Chapter 1").
  final String topicName;

  /// The file size in bytes (0 when unknown).
  final int fileSize;

  /// The page count for PDF-type resources (0 when unknown).
  final int pageCount;

  /// The duration in seconds for video resources (0 when unknown).
  final int durationSeconds;

  /// Creates a [ResourceModel] with the given metadata.
  ResourceModel({
    required this.id,
    required this.title,
    required this.subject,
    required this.grade,
    required this.type,
    this.isDownloaded = false,
    this.pdfUrl,
    this.mtime = 0,
    this.topicName = '',
    this.fileSize = 0,
    this.pageCount = 0,
    this.durationSeconds = 0,
  });

  /// Creates a [ResourceModel] from a JSON [map] returned by the API.
  factory ResourceModel.fromJson(Map<String, dynamic> json) {
    return ResourceModel(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? '',
      subject: json['subject'] ?? kFallbackSubject,
      grade: json['grade'] ?? '',
      type: parseResourceType(json['type']?.toString() ?? ''),
      pdfUrl: json['pdfUrl'],
      mtime: (json['mtime'] as num?)?.toDouble() ?? 0,
      isDownloaded: json['isDownloaded'] == true,
      topicName: (json['topic_name'] as String?) ?? '',
      fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
      pageCount: (json['page_count'] as num?)?.toInt() ?? 0,
      durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
    );
  }

  /// Serializes this [ResourceModel] to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'subject': subject,
    'grade': grade,
    'type': type.name,
    'pdfUrl': pdfUrl,
    'mtime': mtime,
    'isDownloaded': isDownloaded,
    'topic_name': topicName,
    'file_size': fileSize,
    'page_count': pageCount,
    'duration_seconds': durationSeconds,
  };
}