/// Models for ZIM archive and article data synced from the hub server.
library;

/// A ZIM archive uploaded to the hub.
class ZimArchive {
  /// Server-assigned identifier (e.g. `ZIM-{uuid}`).
  final String id;
  /// Original upload filename on the server filesystem.
  final String filename;
  /// Human-readable archive title from ZIM metadata.
  final String title;
  /// Number of articles extracted from this archive.
  final int articleCount;
  /// ISO 639-1 language code (e.g. `en`, `hi`).
  final String language;
  /// UTC ISO 8601 timestamp of when the archive was uploaded.
  final String uploadedAt;
  /// Archive file size in bytes.
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
  /// Unique article identifier within the archive.
  final String articleId;
  /// Human-readable article title.
  final String title;
  /// Identifier of the parent [ZimArchive].
  final String archiveId;
  /// Path within the ZIM archive.
  final String path;
  /// ZIM namespace (typically `A` for articles, `I` for images).
  final String namespace;
  /// Whether a thumbnail has been extracted for this article.
  final bool hasThumbnail;
  /// Display name of the peer hub hosting this article, empty for local articles.
  final String peerName;

  ZimArticle({
    required this.articleId,
    required this.title,
    required this.archiveId,
    this.path = '',
    this.namespace = 'A',
    this.hasThumbnail = false,
    this.peerName = '',
  });

  /// Whether this article comes from a paired peer hub.
  bool get isPeer => peerName.isNotEmpty;

  factory ZimArticle.fromJson(Map<String, dynamic> json) {
    return ZimArticle(
      articleId: json['article_id'] ?? '',
      title: json['title'] ?? '',
      archiveId: json['archive_id'] ?? '',
      path: json['path'] ?? '',
      namespace: json['namespace'] ?? 'A',
      hasThumbnail: json['has_thumbnail'] ?? false,
      peerName: json['peer_name'] ?? '',
    );
  }
}
