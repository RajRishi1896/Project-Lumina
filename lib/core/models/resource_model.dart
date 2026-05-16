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

  factory Resource.fromJson(Map<String, dynamic> json) {
    return Resource(
      id: json['id'].toString(),
      title: json['title'],
      url: json['url'],
      type: _mapType(json['type']),
    );
  }

  static ResourceType _mapType(String type) {
    switch (type.toLowerCase()) {
      case 'khan':
        return ResourceType.khan;
      case 'textbook':
        return ResourceType.textbook;
      case 'pyq':
        return ResourceType.pyq;
      case 'kiwix':
        return ResourceType.kiwix;
      default:
        return ResourceType.textbook;
    }
  }

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
