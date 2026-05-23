import 'package:flutter/material.dart';

class RecentFile {
  final String id;
  final String title;
  final String type;
  final String time;
  final IconData icon;
  final Color color;

  RecentFile({
    required this.id,
    required this.title,
    required this.type,
    required this.time,
    required this.icon,
    required this.color,
  });
}

class RecentFilesService extends ChangeNotifier {
  static final RecentFilesService _instance = RecentFilesService._internal();
  factory RecentFilesService() => _instance;
  RecentFilesService._internal();

  final List<RecentFile> _recentFiles = [];
  List<RecentFile> get recentFiles => List.unmodifiable(_recentFiles);

  void addRecentFile(RecentFile file) {
    _recentFiles.removeWhere((f) => f.id == file.id);
    _recentFiles.insert(0, file);
    if (_recentFiles.length > 5) _recentFiles.removeLast();
    notifyListeners();
  }
}
/*import 'package:flutter/material.dart';

class RecentFile {
  final String title;
  final String type;
  final String time;
  final IconData icon;
  final Color color;
  RecentFile({required this.title, required this.type, required this.time, required this.icon, required this.color});
}

class RecentFilesService extends ChangeNotifier {
  static final RecentFilesService _instance = RecentFilesService._internal();

  factory RecentFilesService() {
    return _instance;
  }

  RecentFilesService._internal();

  // Define the list once, with the starting data inside
  final List<RecentFile> _recentFiles = [
    RecentFile(
      title: 'Demo Textbook', 
      type: 'PDF', 
      time: 'Just now', 
      icon: Icons.picture_as_pdf, 
      color: Colors.red
    ),
  ];

  List<RecentFile> get recentFiles => List.unmodifiable(_recentFiles);

  void addFile(RecentFile file) {
    _recentFiles.removeWhere((item) => item.title == file.title);
    _recentFiles.insert(0, file);
    if (_recentFiles.length > 5) _recentFiles.removeLast();
    notifyListeners();
  }
}*/