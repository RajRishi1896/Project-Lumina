import '../utils/file_utils.dart';

/// The category of a learning resource.
enum ResourceType {
  /// Textbooks and reference books.
  textbook,
  /// Video lectures and recordings.
  videos,
  /// Previous year question papers.
  pyq,
  /// Study notes and summaries.
  notes,
  /// Past examination papers.
  pastPaper,
  /// Kiwix offline content (ZIM files).
  kiwix,
}

/// A model representing a learning resource with its metadata and download status.
///
/// The fallback subject [kFallbackSubject] can be overridden with a localized
/// string where a [BuildContext] is available.
const String kFallbackSubject = 'General';

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

  /// Optional teacher-provided notes for this resource.
  final String? notes;

  /// Whether this resource has been downloaded to the device.
  bool isDownloaded;

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
    this.notes,
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
      notes: json['notes'] as String?,
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
    'notes': notes,
  };
}