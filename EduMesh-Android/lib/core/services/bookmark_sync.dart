import 'package:flutter/foundation.dart';
import '../network/api_client.dart';
import '../storage/db_helper.dart';
import 'mutation_queue.dart';
import '../../shared/services/connectivity_service.dart';

/// Central backup for Saved bookmarks.
///
/// The local `bookmarks` table is the source of truth. Every bookmark
/// mutation funnels its server backup through [push]: a direct POST when
/// online, a queued POST when offline (the `submitQuiz` pattern via
/// [MutationQueue]). The server prunes ids missing from a sync-write, so a
/// full-list push also propagates unsaves.
class BookmarkSync {
  BookmarkSync._();

  /// Full-list backup endpoint (parallel server track contract).
  static const String syncEndpoint = '/student/sync-bookmarks';

  /// Full-list fetch endpoint (parallel server track contract).
  static const String fetchEndpoint = '/student/bookmarks';

  /// Raw bookmark `type` values that never live in the resource catalog, so
  /// catalog absence must never mark them deleted.
  static bool isCatalogBacked(String rawType) {
    final t = rawType.trim().toLowerCase();
    return t != 'kiwix' && t != 'course' && t.isNotEmpty;
  }

  /// Pure: ids present locally but missing server-side (offline-created).
  /// Non-empty means [push] back is needed after a pull.
  static Set<String> localOnlyIds(Set<String> localIds, Set<String> serverIds) =>
      localIds.difference(serverIds);

  /// Pure: server rows whose id is absent locally. Only these are inserted:
  /// local titles are never overwritten.
  static List<Map<String, dynamic>> missingForInsert(
    List<Map<String, dynamic>> serverBookmarks,
    Set<String> localIds,
  ) =>
      serverBookmarks
          .where((b) => !localIds.contains((b['resource_id'] ?? '').toString()))
          .toList();

  /// Pure: whether a saved item renders the deleted tombstone. Never true
  /// while offline, on a stale cache, when the catalog still holds the id,
  /// or for types the catalog never contains (ZIM articles, courses).
  static bool isTombstoneEligible({
    required bool isOnline,
    required bool catalogFresh,
    required bool inCatalog,
    required String rawType,
  }) =>
      isOnline && catalogFresh && isCatalogBacked(rawType) && !inCatalog;

  /// Pushes the full local list to [syncEndpoint]. Direct POST when online,
  /// [MutationQueue] POST when offline. Never throws.
  static Future<void> push() async {
    try {
      final rows = await DBHelper().getBookmarkedResources();
      final items = rows
          .map((b) => {
                'resource_id': b['resource_id']?.toString() ?? '',
                'title': b['title']?.toString() ?? '',
                'subject': b['subject']?.toString() ?? '',
                'grade': b['grade']?.toString() ?? '',
                'resource_type': b['type']?.toString() ?? '',
              })
          .where((m) => (m['resource_id'] as String).isNotEmpty)
          .toList();
      await MutationQueue().enqueue(syncEndpoint, method: 'POST', body: {'bookmarks': items});
    } catch (e) {
      debugPrint('BookmarkSync: push failed; $e');
    }
  }

  /// Converges local and server copies after login success and after
  /// enrollment-restore, while online only. Inserts locally-missing ids
  /// without touching local titles, then pushes back only when local holds
  /// ids the server did not return (offline-created convergence). Never
  /// throws.
  static Future<void> convergeAfterLogin() async {
    try {
      if (!ConnectivityService().isOnline) return;
      final resp = await ApiClient.get(fetchEndpoint).timeout(const Duration(seconds: 10));
      final data = resp.data;
      final raw = data is Map && data['bookmarks'] is List
          ? (data['bookmarks'] as List).whereType<Map>().toList()
          : const <Map>[];
      final server = [for (final b in raw) Map<String, dynamic>.from(b)];
      final db = DBHelper();
      final localIds = await db.getBookmarkedIds();
      for (final b in missingForInsert(server, localIds)) {
        final id = (b['resource_id'] ?? '').toString();
        if (id.isEmpty) continue;
        await db.upsertBookmark(
          id,
          (b['title'] ?? '').toString(),
          (b['subject'] ?? '').toString(),
          (b['grade'] ?? '').toString(),
          (b['resource_type'] ?? b['type'] ?? '').toString(),
        );
      }
      final serverIds = server.map((b) => (b['resource_id'] ?? '').toString()).toSet();
      if (localOnlyIds(localIds, serverIds).isNotEmpty) await push();
    } catch (e) {
      debugPrint('BookmarkSync: converge failed; $e');
    }
  }
}
