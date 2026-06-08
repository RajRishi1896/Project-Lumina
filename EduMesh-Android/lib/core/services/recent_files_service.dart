import 'package:flutter/material.dart';

/// A data model representing a recently opened file with its display metadata.
class RecentFile {
  /// The unique identifier of the file.
  final String id;

  /// The display title of the file.
  final String title;

  /// The file type label (e.g. "PDF", "Video").
  final String type;

  /// A human-readable relative time string (e.g. "2m ago").
  final String time;

  /// The icon representing the file type.
  final IconData icon;

  /// The accent color associated with the file type.
  final Color color;

  /// Creates a [RecentFile] with all required display properties.
  RecentFile({
    required this.id,
    required this.title,
    required this.type,
    required this.time,
    required this.icon,
    required this.color,
  });
}

/// A singleton [ChangeNotifier] that maintains a bounded list of recently opened files.
class RecentFilesService extends ChangeNotifier {
  static final RecentFilesService _instance = RecentFilesService._internal();
  factory RecentFilesService() => _instance;
  RecentFilesService._internal();

  final List<RecentFile> _recentFiles = [];

  /// An unmodifiable snapshot of the most recent files (max 5).
  List<RecentFile> get recentFiles => List.unmodifiable(_recentFiles);

  /// Inserts [file] at the top of the recent list, removing duplicates and
  /// capping the list at 5 entries. Notifies listeners after the change.
  void addRecentFile(RecentFile file) {
    _recentFiles.removeWhere((f) => f.id == file.id);
    _recentFiles.insert(0, file);
    if (_recentFiles.length > 5) _recentFiles.removeLast();
    notifyListeners();
  }
}