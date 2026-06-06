import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/storage/db_helper.dart';
import '../../shared/services/download_service.dart';

/// A page that lists all resources downloaded for offline access.
///
/// Reads from the local SQLite database via [DBHelper] and displays each
/// resource's title, subject, type icon, and file size. Supports deleting
/// individual downloads.
class OfflineLibraryPage extends StatefulWidget {
  const OfflineLibraryPage({super.key});

  @override
  State<OfflineLibraryPage> createState() => _OfflineLibraryPageState();
}

class _OfflineLibraryPageState extends State<OfflineLibraryPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await DBHelper().getDownloadedResources();
    final List<Map<String, dynamic>> withSizes = [];
    for (final r in rows) {
      final path = r['local_path'] as String?;
      int size = 0;
      if (path != null) {
        final f = File(path);
        if (await f.exists()) size = await f.length();
      }
      withSizes.add({...r, 'size': size});
    }
    if (mounted) setState(() { _items = withSizes; _loading = false; });
  }

  Future<void> _delete(String resourceId, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Download'),
        content: Text('Delete "$title" from offline storage?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      await DownloadService().deleteDownload(resourceId);
      _load();
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'textbook': return Icons.menu_book;
      case 'video': case 'videos': return Icons.play_circle;
      case 'pyq': return Icons.description;
      case 'kiwix': return Icons.language;
      default: return Icons.article;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Offline Library'),
        backgroundColor: cs.surface,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.download_outlined, size: 64.sp, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                      SizedBox(height: 16.h),
                      Text('No downloaded resources', style: TextStyle(fontSize: 16.sp, color: cs.onSurfaceVariant)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.all(16.w),
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final title = item['title'] as String? ?? '';
                    final subject = item['subject'] as String? ?? '';
                    final type = item['type'] as String? ?? '';
                    final size = item['size'] as int? ?? 0;
                    final resourceId = item['resource_id'] as String? ?? '';
                    return Card(
                      margin: EdgeInsets.only(bottom: 8.h),
                      child: ListTile(
                        leading: Icon(_iconForType(type), color: cs.primary),
                        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('$subject • ${_formatSize(size)}', style: TextStyle(fontSize: 12.sp)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _delete(resourceId, title),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
