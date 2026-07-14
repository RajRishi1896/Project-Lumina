import 'dart:io';
import 'package:flutter/material.dart';
import '../models/resource_model.dart';
import '../../l10n/app_localizations.dart';

/// Parses a resource type string into a [ResourceType] enum value.
///
/// Accepts common casing variants and plural forms: "textbook", "video"/"videos",
/// "pyq", "pastpaper"/"past_paper", "kiwix".
/// Defaults to [ResourceType.textbook] for unrecognised input.
ResourceType parseResourceType(String type) {
  switch (type.toLowerCase()) {
    case 'textbook':
      return ResourceType.textbook;
    case 'videos':
    case 'video':
      return ResourceType.videos;
    case 'pyq':
      return ResourceType.pyq;
    case 'pastpaper':
    case 'past_paper':
      return ResourceType.pastPaper;
    case 'kiwix':
      return ResourceType.kiwix;
    default:
      return ResourceType.textbook;
  }
}

/// Formats a byte count into a human-readable string with localised units.
///
/// Returns values like "1.2 MB" or "900 B". Uses [l10n] for unit labels.
String formatFileSize(int bytes, AppLocalizations l10n) {
  if (bytes < 1024) return '$bytes${l10n.unitBytes}';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}${l10n.unitKilobytes}';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}${l10n.unitMegabytes}';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}${l10n.unitGigabytes}';
}

/// Returns the Material [IconData] for a given [ResourceType].
IconData iconForType(ResourceType type) {
  switch (type) {
    case ResourceType.textbook:
      return Icons.menu_book_rounded;
    case ResourceType.videos:
      return Icons.play_circle_rounded;
    case ResourceType.pyq:
      return Icons.assignment_rounded;

    case ResourceType.kiwix:
      return Icons.language_rounded;
    case ResourceType.pastPaper:
      return Icons.assignment_rounded;
  }
}

/// Recursively computes the total size (in bytes) of all files in [dir].
///
/// Returns 0 if the directory does not exist or an error occurs during traversal.
Future<int> getDirSize(Directory dir) async {
  int totalSize = 0;
  try {
    if (await dir.exists()) {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
    }
  } catch (_) {}
  return totalSize;
}
