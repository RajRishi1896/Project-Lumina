/// Models for ZIM archive and article data synced from the hub server.
library;

/// A ZIM archive uploaded to the hub.
class ZimArchive {
  final String id;
  final String filename;
  final String title;
  final int articleCount;
  final String language;
  final String uploadedAt;
  final int fileSize;

  ZimArchive({
    required this.id,
    required this.filename,
    required this.title,
    required this.articleCount,
    required this.language,
    required this.uploadedAt,
    required this.fileSize,
  });

  factory ZimArchive.fromJson(Map<String, dynamic> json) {
    return ZimArchive(
      id: json['id'] ?? '',
      filename: json['filename'] ?? '',
      title: json['title'] ?? '',
      articleCount: json['article_count'] ?? 0,
      language: json['language'] ?? 'en',
      uploadedAt: json['uploaded_at'] ?? '',
      fileSize: json['file_size'] ?? 0,
    );
  }
}

/// A single article within a ZIM archive.
class ZimArticle {
  final String articleId;
  final String title;
  final String archiveId;
  final bool hasThumbnail;

  ZimArticle({
    required this.articleId,
    required this.title,
    required this.archiveId,
    this.hasThumbnail = false,
  });

  factory ZimArticle.fromJson(Map<String, dynamic> json) {
    return ZimArticle(
      articleId: json['article_id'] ?? '',
      title: json['title'] ?? '',
      archiveId: json['archive_id'] ?? '',
      hasThumbnail: json['has_thumbnail'] ?? false,
    );
  }
}
