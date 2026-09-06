import 'dart:async';
import 'package:edumesh_android/core/navigation/lumina_transitions.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/lumina_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/models/resource_model.dart';
import '../../core/storage/db_helper.dart';
import '../../core/utils/file_utils.dart';
import '../../shared/services/download_service.dart';
import '../../shared/services/download_queue.dart';
import '../../shared/services/zim_download_helper.dart';
import '../../shared/services/zim_sync_service.dart';
import '../../features/dashboard/presentation/kiwix_view.dart';
import '../../core/network/api_client.dart';
import '../../core/services/recent_resources.dart';
import 'pdf_viewer_page.dart';
import 'video_player_page.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';

/// Attaches each row's on-disk size in a single background-isolate pass.
///
/// Returns a new list and leaves the input rows untouched. Runs inside
/// [compute] so the per-file `stat()` calls never block the UI isolate.
List<Map<String, dynamic>> _attachSizes(List<Map<String, dynamic>> rows) {
  final withSizes = <Map<String, dynamic>>[];
  for (final r in rows) {
    final path = r['local_path'] as String?;
    int size = 0;
    if (path != null && path.isNotEmpty) {
      final f = File(path);
      try {
        if (f.existsSync()) size = f.lengthSync();
      } catch (_) {}
    }
    withSizes.add({...r, 'size': size});
  }
  return withSizes;
}

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
    // Filter out individual course resources — they are shown as course
    // cards via the Saved Resources > Courses tab.
    final courseRids = await DBHelper().getCourseResourceIds();
    final filteredRows = rows.where((r) => !courseRids.contains(r['resource_id']?.toString() ?? '')).toList();
    final List<Map<String, dynamic>> allRows = [...filteredRows, ...zimRows];
    // File-size lookups are batched into one background-isolate compute pass
    // so the UI isolate never performs per-file I/O and build stays pure.
    final withSizes = await compute(_attachSizes, allRows);
    if (mounted) setState(() { _items = withSizes; _loading = false; });
  }

  Future<void> _delete(String resourceId, String title, Map<String, dynamic> item) async {
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
      final isZim = item['is_zim'] == true;
      if (isZim) {
        final articleId = (item['article_id'] as String?) ?? '';
        if (articleId.isNotEmpty) {
          // Delete the article directory from disk.
          await ZimDownloadHelper.deleteArticle(articleId);
          // Reset the download flag in the local DB.
          final db = await DBHelper().database;
          await db.update('zim_articles_local', {'is_downloaded': 0},
              where: 'article_id = ?', whereArgs: [articleId]);
          // Update the in-memory set so the browse UI stops showing it as downloaded.
          ZimSyncService.instance.unmarkDownloaded(articleId);
          // Remove cached page preference.
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('zim_page_$articleId');
          } catch (_) {}
        }
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
        // Theme appBarTheme pairs a primary background with onPrimary
        // foreground; this page uses a surface background, so the foreground
        // must be overridden to match or both title and icon render white.
        foregroundColor: cs.onSurface,
        backgroundColor: cs.surface,
      ),
      body: Column(
        children: [
          _buildQueueSection(context, cs, tt, l10n),
          Expanded(
            child: _loading
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
                    : Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
                          child: ListView.builder(
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
                    final isRemoved = (item['server_removed'] as num? ?? 0) == 1;
                    return Card(
                      margin: EdgeInsets.only(bottom: AppSpacing.sm.h),
                      child: ListTile(
                        leading: Icon(
                          isZim ? Icons.menu_book : iconForType(parseResourceType(type)),
                          color: cs.primary,
                        ),
                        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isZim ? 'Wikipedia' : '$subject • ${formatFileSize(size, l10n)}',
                              style: tt.bodySmall,
                            ),
                            if (isRemoved) ...[
                              SizedBox(height: AppSpacing.xs.h),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm.w, vertical: AppSpacing.xs.h),
                                decoration: BoxDecoration(
                                  color: cs.errorContainer,
                                  borderRadius: BorderRadius.circular(4.r),
                                ),
                                child: Text(
                                  l10n.removedFromServerBadge,
                                  style: tt.labelSmall?.copyWith(color: cs.onErrorContainer),
                                ),
                              ),
                            ],
                          ],
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
                                  unawaited(Navigator.push(context, luminaRoute(
                                    builder: (_) => KiwixView(initialHtml: html, title: title, baseUrl: ApiClient.baseUrl),
                                  )));
                                }
                              },
                            ),
                          IconButton(
                            icon: Icon(Icons.delete_outline, color: cs.error),
                            onPressed: () => _delete(resourceId, title, item),
                            tooltip: l10n.tooltipDeleteDownload(title),
                          ),
                        ]),
                        onTap: () => _openItem(item, isZim),
                      ),
                    );
                  },
                    ),
                  ),
                ),
          ),
        ],
      ),
    );
  }

  /// Active + queued downloads with cancel actions. Hidden when idle so the
  /// downloaded list owns the screen; rebuilds only on queue changes.
  Widget _buildQueueSection(
      BuildContext context, ColorScheme cs, TextTheme tt, AppLocalizations l10n) {
    return ListenableBuilder(
      listenable: DownloadQueue(),
      builder: (context, _) {
        final queue = DownloadQueue();
        final ids = queue.queuedIds.toList();
        if (ids.isEmpty) return const SizedBox.shrink();
        final active = queue.active;
        return Container(
          padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.lg.w, vertical: AppSpacing.sm.h),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            border: Border(bottom: BorderSide(color: cs.outlineVariant)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(l10n.downloadQueueTitle,
                        style: tt.titleSmall
                            ?.copyWith(color: cs.onSurface)),
                  ),
                  TextButton(
                    onPressed: () => queue.clear(),
                    child: Text(l10n.downloadQueueClearAll,
                        style: tt.bodyMedium?.copyWith(color: cs.error)),
                  ),
                ],
              ),
              for (final id in ids)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: id == active
                      ? SizedBox(
                          width: AppSpacing.xxl.w,
                          height: AppSpacing.xxl.w,
                          child: const CircularProgressIndicator(
                              strokeWidth: 2))
                      : Icon(Icons.hourglass_empty_rounded,
                          color: cs.onSurfaceVariant),
                  title: Text(id,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: tt.bodyMedium),
                  subtitle: id == active
                      ? Text(l10n.downloadQueueDownloading,
                          style: tt.bodySmall
                              ?.copyWith(color: cs.primary))
                      : null,
                  trailing: IconButton(
                    icon: Icon(Icons.close,
                        size: 18, color: cs.onSurfaceVariant),
                    onPressed: () => queue.cancel(id),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openItem(Map<String, dynamic> item, bool isZim) async {
    if (!isZim) {
      final path = item['local_path'] as String?;
      if (path == null || path.isEmpty) return;
      final title = item['title'] as String? ?? '';
      final subject = item['subject'] as String? ?? '';
      if (parseResourceType(item['type'] as String? ?? '') == ResourceType.videos) {
        unawaited(Navigator.of(context).push(luminaRoute(
          builder: (_) => VideoPlayerPage(title: title, videoUrl: path, subject: subject),
        )));
      } else {
        unawaited(Navigator.of(context).push(luminaRoute(
          builder: (_) => PdfViewerPage(title: title, pdfUrl: path, subject: subject),
        )));
      }
      return;
    }
    final articleId = item['article_id'] as String? ?? '';
    if (articleId.isEmpty) return;
    String? html;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/zim_${articleId.replaceAll('/', '_')}.html');
      if (await file.exists()) html = await file.readAsString();
    } catch (_) {}
    if (html == null || !context.mounted) return;
    unawaited(RecentResources.record(articleId, item['title'] as String? ?? '', 'kiwix'));
    unawaited(Navigator.push(context, luminaRoute(
      builder: (_) => KiwixView(initialHtml: html, title: item['title'] as String? ?? '', baseUrl: ApiClient.baseUrl),
    )));
  }
}
