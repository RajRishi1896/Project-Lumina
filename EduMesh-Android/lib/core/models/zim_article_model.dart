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

  /// Parses a [ZimArchive] from a server JSON [map].
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
  /// Human-readable article title.
  final String title;
  /// Identifier of the parent [ZimArchive].
  final String archiveId;
  /// Path within the ZIM archive.
  final String path;
  /// ZIM namespace (typically `A` for articles, `I` for images).
  final String namespace;
  /// Whether `zim_pages/thumbs/{article}.png` exists on the server.
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

  bool get isPeer => peerName.isNotEmpty;

  /// Parses a [ZimArticle] from a server JSON [map].
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
