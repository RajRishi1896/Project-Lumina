import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/network/api_client.dart';

/// Saves a ZIM article's HTML and assets to disk as separate files.
///
/// Instead of base64-inlining every asset into one bloated HTML file,
/// this writes each asset as a standalone file. The HTML is rewritten
/// with relative paths so `WebView.loadFile()` resolves them from the
/// article's directory — zero base64 overhead.
class ZimDownloadHelper {
  ZimDownloadHelper._();

  static final _assetPattern = RegExp(
    r"""(/zim/asset\?archive_id=[^"'&]+&path=([^"'&]+)(?:&h=[^"'&]+)?)""");

  /// Directory name prefix for saved articles.
  static const _dirPrefix = 'zim_';

  /// Returns the article directory path for [articleId].
  static Future<String> _articleDir(String articleId) async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$_dirPrefix$articleId';
  }

  /// Returns the `index.html` path for a saved article, or null.
  static Future<String?> findSavedArticle(String articleId) async {
    try {
      final adir = await _articleDir(articleId);
      final file = File('$adir/index.html');
      if (await file.exists()) return file.path;
    } catch (_) {}
    return null;
  }

  /// Downloads article HTML + all referenced assets to disk.
  ///
  /// Returns the file path to `index.html`. Assets are saved as
  /// separate files under `assets/` alongside the HTML.
  static Future<String> saveArticle({
    required String articleId,
    required String archiveId,
  }) async {
    final res = await ApiClient.get('/zim/page', queryParameters: {
      'article_id': articleId,
      'archive_id': archiveId,
    }).timeout(const Duration(seconds: 10));
    var html = res.data['html'] as String? ?? '';
    if (html.isEmpty) throw Exception('Empty article HTML');

    final adir = await _articleDir(articleId);
    final assetsDir = Directory('$adir/assets');
    await assetsDir.create(recursive: true);

    final matches = _assetPattern.allMatches(html).toList();

    // ponytail: 5 concurrent fetches, same as old code. Bump if bandwidth allows.
    const concurrency = 5;
    for (var i = 0; i < matches.length; i += concurrency) {
      final batch = matches.sublist(i, (i + concurrency).clamp(0, matches.length));
      await Future.wait(batch.map((m) async {
        final fullUrl = m.group(1)!;
        final assetPath = Uri.decodeComponent(m.group(2)!);
        try {
          final assetResp = await ApiClient.getBinary('/zim/asset', queryParameters: {
            'archive_id': archiveId,
            'path': assetPath,
          }).timeout(const Duration(seconds: 5));
          if (assetResp.data == null || assetResp.data!.isEmpty) return;
          // Sanitize the full ZIM path into a flat filename.
          final safeName = assetPath.replaceAll('/', '__');
          final assetFile = File('${assetsDir.path}/$safeName');
          await assetFile.writeAsBytes(assetResp.data!);
          html = html.replaceAll(fullUrl, 'assets/$safeName');
        } catch (_) {
          // Asset fetch failed: leave URL as-is (dead link in offline HTML).
        }
      }));
    }

    final file = File('$adir/index.html');
    await file.writeAsString(html);
    debugPrint('ZimDownloadHelper: saved $articleId → ${file.path} '
        '(${matches.length} assets)');
    return file.path;
  }

  /// Deletes a saved article and its assets directory.
  static Future<void> deleteArticle(String articleId) async {
    try {
      final adir = Directory(await _articleDir(articleId));
      if (await adir.exists()) await adir.delete(recursive: true);
    } catch (_) {}
  }
}
