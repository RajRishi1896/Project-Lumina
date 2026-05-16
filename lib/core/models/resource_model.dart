enum ResourceType { kiwix, khan, textbook, pyq }

class Resource {
  final String id;
  final String title;
  final String url;
  final ResourceType type;
  final String? localPath;
  final bool isDownloaded;

  Resource({
    required this.id,
    required this.title,
    required this.url,
    required this.type,
    this.localPath,
    this.isDownloaded = false,
  });

  Resource copyWith({
    String? localPath,
    bool? isDownloaded,
  }) {
    return Resource(
      id: id,
      title: title,
      url: url,
      type: type,
      localPath: localPath ?? this.localPath,
      isDownloaded: isDownloaded ?? this.isDownloaded,
    );
  }
}
