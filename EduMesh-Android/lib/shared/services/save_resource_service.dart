import 'package:flutter/material.dart';
import 'package:edumesh_android/core/models/resource_model.dart';
import 'package:edumesh_android/core/services/activity_tracker.dart';
import 'package:edumesh_android/core/storage/db_helper.dart';

/// Service for toggling and querying saved (bookmarked) resources.
///
/// The fallback title [kFallbackTitle] can be overridden with a localized
/// string on app startup (e.g. from [LuminaApp.build]).
const String kFallbackTitle = 'Untitled';

/// Operates on the local SQLite database via [DBHelper] and logs save/unsave
/// actions to the [ActivityTracker].
class SaveResourceService {
  /// Toggles the saved status of a resource identified by [id].
  ///
  /// Returns `true` if the resource was saved, `false` if it was unsaved.
  /// Logs the action via [ActivityTracker].
  static Future<bool> toggleSaveStatus(
    String id, {
    String? title,
    String? subject,
    String? grade,
    String? type,
    String? pdfUrl,
  }) async {
    try {
      final db = DBHelper();
      final bookmarked = await db.getBookmarkedIds();
      if (bookmarked.contains(id)) {
        await db.removeBookmark(id);
        ActivityTracker().logKeyAction('unsave', resourceId: id, metadata: title ?? '');
        return false;
      }
      await db.upsertBookmark(
        id,
        title ?? kFallbackTitle,
        subject ?? '',
        grade ?? '',
        type ?? '',
        pdfUrl: pdfUrl,
      );
      ActivityTracker().logKeyAction('save', resourceId: id, metadata: title ?? '');
      return true;
    } catch (e) {
      debugPrint('Error toggling bookmark: $e');
      return false;
    }
  }

  /// All saved resources as a list of [ResourceModel] instances.
  static Future<List<ResourceModel>> getAllSavedResourceModels() async {
    final db = DBHelper();
    final rows = await db.getBookmarkedResources();
    return rows.map((r) => ResourceModel(
      id: r['resource_id'] as String? ?? '',
      title: r['title'] as String? ?? '',
      subject: r['subject'] as String? ?? '',
      grade: r['grade'] as String? ?? '',
      type: parseType(r['type'] as String? ?? ''),
      pdfUrl: r['pdf_url'] as String?,
    )).toList();
  }

  /// Whether the resource with [id] is currently saved.
  static Future<bool> isSaved(String id) async {
    final db = DBHelper();
    final bookmarked = await db.getBookmarkedIds();
    return bookmarked.contains(id);
  }

  /// Saved resources filtered by [ResourceType].
  static Future<List<ResourceModel>> getSavedByType(ResourceType type) async {
    final all = await getAllSavedResourceModels();
    return all.where((r) => r.type == type).toList();
  }

  /// Distinct subject names from both saved and downloaded resources.
  static Future<List<Map<String, dynamic>>> getDistinctSubjects() async {
    final db = DBHelper();
    final bookmarks = await db.getBookmarkedResources();
    final downloads = await db.getDownloadedResources();
    final subjects = <String>{};
    for (final r in bookmarks) {
      final s = r['subject'] as String? ?? '';
      if (s.isNotEmpty) subjects.add(s);
    }
    for (final r in downloads) {
      final s = r['subject'] as String? ?? '';
      if (s.isNotEmpty) subjects.add(s);
    }
    return subjects.map((s) => {'name': s}).toList();
  }

  /// Parses a string [type] into the corresponding [ResourceType] enum value.
  ///
  /// Accepts `'textbook'`, `'videos'` / `'video'`, `'pyq'`, and `'kiwix'`;
  /// anything else defaults to [ResourceType.notes].
  static ResourceType parseType(String type) {
    switch (type.toLowerCase()) {
      case 'textbook':
        return ResourceType.textbook;
      case 'videos':
      case 'video':
        return ResourceType.videos;
      case 'pyq':
        return ResourceType.pyq;
      case 'kiwix':
        return ResourceType.kiwix;
      default:
        return ResourceType.notes;
    }
  }
}