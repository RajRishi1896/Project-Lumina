import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service that manages cached HTML pages fetched from the ZIM server.
///
/// Cached files are stored under the app's private documents directory
/// in a sub‑folder `zim_pages/`. Each file is named `<articleId>.html`.
/// The service also stores the last‑access timestamp in SharedPreferences
/// so the auto‑cleaner can purge old entries.
class ZimCacheService {
  static const String _folderName = 'zim_pages';

  /// Returns the directory where cached pages are stored, creating it if needed.
  static Future<Directory> _cacheDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_folderName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Save HTML content for the given [articleId] and record the access time.
  static Future<void> savePage(String articleId, String html) async {
    final dir = await _cacheDir();
    final file = File('${dir.path}/$articleId.html');
    await file.writeAsString(html, flush: true);
    await _updateAccessTime(articleId);
  }

  /// Retrieve cached HTML for [articleId] if it exists, otherwise null.
  static Future<String?> getPage(String articleId) async {
    final dir = await _cacheDir();
    final file = File('${dir.path}/$articleId.html');
    if (await file.exists()) {
      await _updateAccessTime(articleId);
      return await file.readAsString();
    }
    return null;
  }

  /// Check whether a page is cached.
  static Future<bool> isCached(String articleId) async {
    final dir = await _cacheDir();
    return await File('${dir.path}/$articleId.html').exists();
  }

  /// Delete a specific cached page.
  static Future<void> deletePage(String articleId) async {
    final dir = await _cacheDir();
    final file = File('${dir.path}/$articleId.html');
    if (await file.exists()) {
      await file.delete();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('zim_access_$articleId');
  }

  /// Delete all cached pages.
  static Future<void> clearAll() async {
    final dir = await _cacheDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('zim_access_')).toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
    // Re‑create empty folder for future caching
    await dir.create(recursive: true);
  }

  /// Update the last‑access timestamp for a cached article.
  static Future<void> _updateAccessTime(String articleId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('zim_access_$articleId', DateTime.now().millisecondsSinceEpoch);
  }

  /// Get the last‑access timestamp (ms since epoch) for an article, or null.
  static Future<int?> getLastAccess(String articleId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('zim_access_$articleId');
  }
}
