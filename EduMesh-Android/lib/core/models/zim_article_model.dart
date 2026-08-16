/// Models for ZIM archive and article data synced from the hub server.
library;

/// A single article within a ZIM archive.
class ZimArticle {
  final String articleId;
  /// Human-readable article title.
  final String title;
  /// Identifier of the parent ZIM archive.
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
