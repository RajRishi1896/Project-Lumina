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
  });

  /// Creates a [ResourceModel] from a JSON [map] returned by the API.
  factory ResourceModel.fromJson(Map<String, dynamic> json) {
    return ResourceModel(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? '',
      subject: json['subject'] ?? 'General',
      grade: json['grade'] ?? '',
      type: _parseType(json['type']?.toString() ?? ''),
      pdfUrl: json['pdfUrl'],
      mtime: (json['mtime'] as num?)?.toDouble() ?? 0,
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
      case 'pastpaper':
      case 'past_paper':
        return ResourceType.pastPaper;
      case 'kiwix':
        return ResourceType.kiwix;
      case 'notes':
      case 'note':
        return ResourceType.notes;
      default:
        return ResourceType.notes;
    }
  }
}