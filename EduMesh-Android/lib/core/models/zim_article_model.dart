/// Models for ZIM archive and article data synced from the hub server.
library;

/// A single article within a ZIM archive.
class ZimArticle {
  final String articleId;
  /// Human-readable article title.
  final String title;
  /// Identifier of the parent ZIM archive.
  final String archiveId;
  /// Whether `zim_pages/thumbs/{article}.png` exists on the server.
  final bool hasThumbnail;

  ZimArticle({
    required this.articleId,
    required this.title,
    required this.archiveId,
    this.hasThumbnail = false,
  });
}
