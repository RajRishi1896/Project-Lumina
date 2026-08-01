import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/constants/lumina_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/storage/db_helper.dart';
import '../../core/utils/file_utils.dart';
import '../../shared/services/download_service.dart';
import '../../features/dashboard/presentation/kiwix_view.dart';
import '../../core/network/api_client.dart';
import '../../core/services/recent_resources.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';

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
    final zimRows = await DBHelper().getDownloadedZimArticles();
    final List<Map<String, dynamic>> allRows = [...rows, ...zimRows];
    final List<Map<String, dynamic>> withSizes = [];
    for (final r in allRows) {
      final path = r['local_path'] as String?;
      int size = 0;
      if (path != null && path.isNotEmpty) {
        final f = File(path);
        if (await f.exists()) size = await f.length();
      }
      withSizes.add({...r, 'size': size});
    }
    if (mounted) setState(() { _items = withSizes; _loading = false; });
  }

  Future<void> _delete(String resourceId, String title) async {
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteDownloadDialogTitle),
        content: Text(l10n.deleteDownloadConfirmation(title)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.buttonCancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.deleteConfirmButtonLabel, style: tt.labelSmall?.copyWith(color: LuminaColors.danger))),
        ],
      ),
    );
    if (confirmed == true) {
      final isZim = resourceId.startsWith('zim_');
      if (isZim) {
        final articleId = resourceId.substring(4);
        await DBHelper().markZimArticleDownloaded(articleId);
        final db = await DBHelper().database;
        await db.update('zim_articles_local', {'is_downloaded': 0},
            where: 'article_id = ?', whereArgs: [articleId]);
      } else {
        await DownloadService().deleteDownload(resourceId);
      }
      unawaited(_load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(l10n.offlineLibraryAppBarTitle),
        backgroundColor: cs.surface,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.download_outlined, size: 64.sp, color: cs.onSurfaceVariant),
                      SizedBox(height: AppSpacing.lg.h),
                      Text(l10n.emptyOfflineLibraryMessage, style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.all(AppSpacing.lg.w),
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final title = item['title'] as String? ?? '';
                    final subject = item['subject'] as String? ?? '';
                    final type = item['type'] as String? ?? '';
                    final size = item['size'] as int? ?? 0;
                    final resourceId = item['resource_id'] as String? ?? '';
                    final isZim = item['is_zim'] == true;
                    return Card(
                      margin: EdgeInsets.only(bottom: AppSpacing.sm.h),
                      child: ListTile(
                        leading: Icon(
                          isZim ? Icons.menu_book : iconForType(parseResourceType(type)),
                          color: cs.primary,
                        ),
                        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          isZim ? 'Wikipedia' : '$subject • ${formatFileSize(size, l10n)}',
                          style: tt.bodySmall,
                        ),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (isZim)
                            IconButton(
                              icon: Icon(Icons.open_in_new, color: cs.primary, size: 20),
                              onPressed: () async {
                                final articleId = item['article_id'] as String? ?? '';
                                if (articleId.isEmpty) return;
                                String? html;
                                try {
                                  final dir = await getApplicationDocumentsDirectory();
                                  final file = File('${dir.path}/zim_${articleId.replaceAll('/', '_')}.html');
                                  if (await file.exists()) html = await file.readAsString();
                                } catch (_) {}
                                if (html != null && context.mounted) {
                                  unawaited(RecentResources.record(articleId, title, 'kiwix'));
                                  Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => KiwixView(initialHtml: html, title: title, baseUrl: ApiClient.baseUrl),
                                  ));
                                }
                              },
                            ),
                          IconButton(
                            icon: Icon(Icons.delete_outline, color: cs.error),
                            onPressed: () => _delete(resourceId, title),
                            tooltip: l10n.tooltipDeleteDownload(title),
                          ),
                        ]),
                        onTap: isZim ? null : null,
                      ),
                    );
                  },
                ),
    );
  }
}
