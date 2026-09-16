import 'dart:async';
import 'dart:io';
import 'package:edumesh_android/core/navigation/lumina_transitions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:edumesh_android/core/models/resource_model.dart';
import 'package:edumesh_android/core/models/course.dart';
import 'package:edumesh_android/core/services/bookmark_sync.dart';
import 'package:edumesh_android/core/services/catalog_service.dart';
import 'package:edumesh_android/core/services/course_service.dart';
import 'package:edumesh_android/shared/services/connectivity_service.dart';
import 'package:edumesh_android/core/storage/db_helper.dart';
import 'package:edumesh_android/core/utils/file_utils.dart';
import 'package:edumesh_android/shared/services/download_service.dart';
import 'package:edumesh_android/shared/services/download_queue.dart';
import 'package:edumesh_android/shared/services/zim_sync_service.dart';
import 'package:edumesh_android/shared/services/zim_download_helper.dart';
import 'package:edumesh_android/core/constants/lumina_colors.dart';
import 'package:edumesh_android/core/constants/app_spacing.dart';
import 'package:edumesh_android/shared/widgets/pdf_viewer_page.dart';
import 'package:edumesh_android/shared/widgets/video_player_page.dart';
import 'package:edumesh_android/core/network/api_client.dart';
import 'package:edumesh_android/core/services/recent_resources.dart';
import 'package:edumesh_android/shared/widgets/resource_thumbnail.dart';
import 'course_player_page.dart';
import 'quiz_player_page.dart';
import 'kiwix_view.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';

void _showDownloadQueue(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  final tt = Theme.of(context).textTheme;
  final l10n = AppLocalizations.of(context)!;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16.r))),
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.5, minChildSize: 0.25, maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return ListenableBuilder(
          listenable: DownloadQueue(),
          builder: (context, _) {
            final queue = DownloadQueue();
            final ids = queue.queuedIds.toList();
            final titles = queue.queuedTitles;
            final active = queue.active;
            return Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w, vertical: AppSpacing.md.h),
                  child: Row(children: [
                    Expanded(child: Text(l10n.downloadQueueTitle,
                      style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                    if (ids.isNotEmpty)
                      TextButton(onPressed: () { queue.clear(); Navigator.pop(context); },
                        child: Text(l10n.downloadQueueClearAll, style: tt.bodyMedium?.copyWith(color: cs.error))),
                  ]),
                ),
                if (ids.isEmpty)
                  Expanded(child: Center(child: Text(l10n.downloadQueueEmpty,
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant))))
                else
                  Expanded(child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (queue.isPaused)
                        Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg.w),
                          child: Row(
                            children: [
                              Icon(Icons.pause_circle_outline,
                                  size: 16, color: cs.onSurfaceVariant),
                              SizedBox(width: AppSpacing.xs.w),
                              Expanded(
                                child: Text(l10n.downloadQueuePaused,
                                    style: tt.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant)),
                              ),
                            ],
                          ),
                        ),
                      Expanded(child: ListView.builder(
                    controller: scrollController,
                    itemCount: ids.length,
                    itemBuilder: (_, i) {
                      final id = ids[i];
                      final isActive = id == active && !queue.isPaused;
                      return ListTile(
                        leading: isActive
                          ? SizedBox(width: AppSpacing.xxl.w, height: AppSpacing.xxl.w, child: CircularProgressIndicator(strokeWidth: 2.w))
                          : Icon(Icons.hourglass_empty_rounded, color: cs.onSurfaceVariant),
                        title: Text(titles[id]?.isNotEmpty == true ? titles[id]! : id, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: tt.bodyMedium),
                        subtitle: isActive ? Text(l10n.downloadQueueDownloading,
                          style: tt.bodySmall?.copyWith(color: cs.primary)) : null,
                        trailing: IconButton(
                          icon: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
                          onPressed: () => queue.cancel(id),
                        ),
                      );
                    },
                  )),
                    ],
                  )),
              ],
            );
          },
        );
      },
    ),
  );
}

/// A page that displays the user's bookmarked resources, organised into
/// tabs for each resource type plus enrolled courses.
class SavedResourcesPage extends StatelessWidget {
  /// Increment to force all child tabs to reload their data.
  static final ValueNotifier<int> refreshNotifier = ValueNotifier(0);

  const SavedResourcesPage({super.key});

  static const _tabLabelStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.w700);
  static const _tabUnselectedStyle = TextStyle(fontSize: 14);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;

    return DefaultTabController(
      length: 8,
      animationDuration: LuminaTransitions.globalEnabled ? kTabScrollDuration : Duration.zero,
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.surface,
          foregroundColor: cs.onSurface,
          elevation: 0,
          // Bottom-nav root tab: never show a back button here.
          automaticallyImplyLeading: false,
          title: Text(
            l10n.savedResourcesTitle,
            style: tt.titleMedium?.copyWith(fontSize: 16.sp, color: cs.onSurface),
          ),
          actions: [
            ListenableBuilder(
              listenable: DownloadQueue(),
              builder: (context, _) {
                final count = DownloadQueue().queuedIds.length;
                return IconButton(
                  onPressed: () => _showDownloadQueue(context),
                  icon: Badge(
                    isLabelVisible: count > 0,
                    label: Text('$count', style: TextStyle(fontSize: 10.sp, color: cs.onPrimary)),
                    child: Icon(Icons.download_rounded, color: cs.onSurfaceVariant),
                  ),
                );
              },
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: cs.primary,
            unselectedLabelColor: cs.onSurfaceVariant,
            indicatorColor: cs.primary,
            indicatorWeight: 3.0,
            labelStyle: _tabLabelStyle,
            unselectedLabelStyle: _tabUnselectedStyle,
            tabs: [
              Tab(text: l10n.tabAll),
              Tab(text: l10n.tabTextbooks),
              Tab(text: l10n.tabVideos),
              Tab(text: l10n.tabPyqs),
              Tab(text: l10n.tabCourses),
              Tab(text: l10n.tabQuizzes),
              Tab(text: l10n.tabNotes),
              Tab(text: l10n.tabZim),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _SavedListByType(),
            _SavedListByType(type: ResourceType.textbook),
            _SavedListByType(type: ResourceType.videos),
            _SavedListByType(type: ResourceType.pyq),
            _SavedCoursesTab(),
            _SavedListByType(type: ResourceType.quiz),
            _SavedListByType(type: ResourceType.notes),
            _SavedListByType(type: ResourceType.kiwix),
          ],
        ),
      ),
    );
  }
}

/// Lists bookmarked resources of a specific [type], or all types if null.
class _SavedListByType extends StatefulWidget {
  final ResourceType? type;
  const _SavedListByType({this.type});

  @override
  State<_SavedListByType> createState() => _SavedListByTypeState();
}

class _SavedListByTypeState extends State<_SavedListByType> {
  List<ResourceModel> _savedItems = [];
  Set<String> _downloadedIds = {};
  Set<String> _removedIds = {};
  Set<String> _tombstoneIds = {};
  final Set<String> _downloadingIds = {};
  final Set<String> _pendingIds = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    SavedResourcesPage.refreshNotifier.addListener(_loadData);
  }

  @override
  void dispose() {
    SavedResourcesPage.refreshNotifier.removeListener(_loadData);
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final db = DBHelper();
      final bookmarkRows = await db.getBookmarkedResources();

      // Saved = bookmarks only. Downloads live in the Downloads page;
      // downloading never implies saving and vice versa.
      final Map<String, ResourceModel> merged = {};

      for (final r in bookmarkRows) {
        final id = r['resource_id'] as String? ?? '';
        if (id.isEmpty) continue;
        // Course saves live in the Courses tab: never leak them into the
        // resource lists (parseResourceType would default them to textbook).
        if ((r['type'] as String? ?? '') == 'course') continue;
        merged[id] = ResourceModel(
          id: id,
          title: r['title'] as String? ?? '',
          subject: r['subject'] as String? ?? '',
          grade: r['grade'] as String? ?? '',
          type: parseResourceType(r['type'] as String? ?? ''),
          pdfUrl: r['pdf_url'] as String?,
        );
      }

      // Bookmarks saved with empty metadata render as blank cards: fill
      // title/subject/grade/type from the local catalog where possible.
      final emptyIds = merged.values
          .where((r) => r.title.trim().isEmpty)
          .map((r) => r.id)
          .toSet();
      if (emptyIds.isNotEmpty) {
        final meta = await db.getCatalogEntries(emptyIds);
        for (final id in emptyIds) {
          final m = meta[id];
          final existing = merged[id]!;
          if (m == null) continue;
          merged[id] = ResourceModel(
            id: id,
            title: (m['title'] as String?)?.trim() ?? '',
            subject: m['subject'] as String? ?? existing.subject,
            grade: m['grade'] as String? ?? existing.grade,
            type: parseResourceType(m['type'] as String? ?? ''),
            pdfUrl: existing.pdfUrl,
          );
        }
      }

      final all = merged.values.toList();
      // In the "All" tab, exclude individual resources that belong to a
      // course (they are shown in the Courses tab as course cards).
      List<ResourceModel> items;
      if (widget.type == null) {
        final courseResourceIds = await db.getCourseResourceIds();
        items = all.where((r) => !courseResourceIds.contains(r.id)).toList();
      } else {
        items = all.where((r) => r.type == widget.type!).toList();
      }
      final ids = await db.getDownloadedIds();
      final downloadRows = await db.getDownloadedResources();
      final removedIds = downloadRows
          .where((r) => (r['server_removed'] as num? ?? 0) == 1)
          .map((r) => r['resource_id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      // Deleted-saved tombstones: online with a freshly synced catalog only.
      // A bookmark absent from the catalog renders a tombstone card. ZIM and
      // course rows never live in the catalog, so they are never flagged, and
      // neither is anything while offline or on a stale cache.
      Set<String> tombstones = {};
      try {
        if (ConnectivityService().isOnline && CatalogService().isFresh) {
          final rawById = {
            for (final r in bookmarkRows)
              (r['resource_id'] as String? ?? ''): (r['type'] as String? ?? '').toString(),
          };
          final courseResourceIds = await db.getCourseResourceIds();
          final candidates = items
              .map((r) => r.id)
              .where((id) =>
                  BookmarkSync.isCatalogBacked(rawById[id] ?? '') &&
                  !courseResourceIds.contains(id))
              .toSet();
          if (candidates.isNotEmpty) {
            final entries = await db.getCatalogEntries(candidates);
            tombstones = candidates.where((id) => !entries.containsKey(id)).toSet();
          }
        }
      } catch (_) {}
      if (mounted) {
        setState(() {
          _savedItems = items;
          _downloadedIds = ids;
          _removedIds = removedIds;
          _tombstoneIds = tombstones;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _toggleSave(String id) async {
    try {
      final db = DBHelper();
      final bookmarked = await db.getBookmarkedIds();
      if (bookmarked.contains(id)) {
        await db.removeBookmark(id);
        unawaited(BookmarkSync.push());
        return false;
      }
      await db.upsertBookmark(id, '', '', '', '');
      unawaited(BookmarkSync.push());
      return true;
    } catch (e) {
      debugPrint('Error toggling bookmark: $e');
      return false;
    }
  }

  /// Removes a tombstoned save locally and backs the removal up.
  Future<void> _unsaveTombstone(String id) async {
    try {
      await DBHelper().removeBookmark(id);
      unawaited(BookmarkSync.push());
    } catch (_) {}
    SavedResourcesPage.refreshNotifier.value++;
    if (mounted) {
      setState(() {
        _savedItems.removeWhere((r) => r.id == id);
        _tombstoneIds.remove(id);
      });
    }
  }

  Future<void> _downloadZimArticle(String articleId, {String title = ''}) async {
    try {
      // Look up archive_id from local DB (persisted by browse on view or
      // bookmark), or resolve via server search as a fallback.
      String archiveId = '';
      final db = DBHelper();
      final rows = await db.database;
      final zimRows = await rows.query('zim_articles_local',
          columns: ['archive_id'], where: 'article_id = ?', whereArgs: [articleId]);
      if (zimRows.isNotEmpty) {
        archiveId = zimRows.first['archive_id'] as String? ?? '';
      }
      if (archiveId.isEmpty && title.isNotEmpty) {
        try {
          final result = await ZimSyncService.instance
              .searchOnServer(title, limit: 50)
              .timeout(const Duration(seconds: 8));
          for (final a in result.articles) {
            if (a.articleId == articleId) {
              archiveId = a.archiveId;
              break;
            }
          }
        } catch (_) {}
      }
      if (archiveId.isEmpty) return;

      await ZimDownloadHelper.saveArticle(articleId: articleId, archiveId: archiveId);
      await ZimSyncService.instance
          .markDownloaded(articleId, title: title, archiveId: archiveId);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('SavedPage: ZIM download failed: $e');
    }
  }

  Future<void> _openItem(ResourceModel item) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    String url = item.pdfUrl ?? '/files/${item.id}';
    if (_downloadedIds.contains(item.id)) {
      final downloads = await DBHelper().getDownloadedResources();
      final match = downloads.where((d) => d['resource_id'] == item.id);
      if (match.isNotEmpty) {
        final localPath = match.first['local_path'] as String?;
        if (localPath != null) url = localPath;
      }
    }
    if (!mounted) return;
    unawaited(RecentResources.record(item.id, item.title, item.type.name));
    if (item.type == ResourceType.videos) {
      unawaited(Navigator.push(context, luminaRoute(
        builder: (_) => VideoPlayerPage(title: item.title, videoUrl: url, subject: item.subject),
      )));
    } else if (item.type == ResourceType.quiz) {
      unawaited(Navigator.push(context, luminaRoute(
        builder: (_) => QuizPlayerPage.fromResource(item),
      )));
    } else if (item.type == ResourceType.kiwix) {
      String articleId = item.id;
      if (articleId.startsWith('zim_')) {
        articleId = articleId.substring(4);
      }
      // New file-based save first, then legacy single-file, prefs, network.
      final savedPath = await ZimDownloadHelper.findSavedArticle(articleId);
      if (savedPath != null) {
        if (!mounted) return;
        unawaited(Navigator.push(context, luminaRoute(
          builder: (_) => KiwixView(filePath: savedPath, title: item.title, subject: item.subject),
        )));
        return;
      }
      String? html;
      try {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/zim_${articleId.replaceAll('/', '_')}.html');
        if (await file.exists()) html = await file.readAsString();
      } catch (_) {}
      if (html == null || html.isEmpty) {
        try {
          final prefs = await SharedPreferences.getInstance();
          html = prefs.getString('zim_page_$articleId');
        } catch (_) {}
      }
      if (html == null || html.isEmpty) {
        try {
          String archiveId = '';
          final db = DBHelper();
          final zimRows = await (await db.database).query('zim_articles_local',
              columns: ['archive_id'], where: 'article_id = ?', whereArgs: [articleId]);
          if (zimRows.isNotEmpty) {
            archiveId = zimRows.first['archive_id'] as String? ?? '';
          }
          if (!context.mounted) return;
          final response = await fetchWithLoading(
            context,
            ApiClient.get('/zim/page', queryParameters: {
              'article_id': articleId,
              if (archiveId.isNotEmpty) 'archive_id': archiveId,
            }).timeout(const Duration(seconds: 8)),
          );
          html = response.data?['html']?.toString();
        } catch (_) {}
      }
      if (!mounted) return;
      if (html != null && html.isNotEmpty) {
        unawaited(Navigator.push(context, luminaRoute(
          builder: (_) => KiwixView(initialHtml: html, title: item.title, baseUrl: ApiClient.baseUrl, subject: item.subject),
        )));
      } else {
        messenger.showSnackBar(SnackBar(content: Text(l10n.zimArticleNotFound)));
      }
    } else {
      unawaited(Navigator.push(context, luminaRoute(
        builder: (_) => PdfViewerPage(title: item.title, pdfUrl: url, subject: item.subject),
      )));
    }
  }

  /// Tombstone card for a save deleted from the hub: plain-language message
  /// plus Unsave, and Open when a local download of the file exists.
  Widget _buildTombstoneCard(ResourceModel item, String displayTitle,
      String resourceId, ColorScheme cs, TextTheme tt, AppLocalizations l10n) {
    final hasDownload = _downloadedIds.contains(resourceId);
    return Container(
      margin: EdgeInsets.only(bottom: AppSpacing.md.h),
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w, vertical: AppSpacing.md.h),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          ResourceThumbnail(resource: item, size: 48),
          SizedBox(width: AppSpacing.md.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(displayTitle,
                    style: tt.titleSmall?.copyWith(color: cs.onSurface),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                SizedBox(height: AppSpacing.xs.h),
                Text(l10n.savedDeletedMessage,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          SizedBox(width: AppSpacing.sm.w),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasDownload)
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(AppSpacing.touchTarget, AppSpacing.touchTarget),
                  ),
                  onPressed: () => _openItem(item),
                  child: Text(l10n.savedOpenFile),
                ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: cs.error,
                  minimumSize: const Size(AppSpacing.touchTarget, AppSpacing.touchTarget),
                ),
                onPressed: () => _unsaveTombstone(resourceId),
                child: Text(l10n.courseUnsave),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_savedItems.isEmpty) {
      final l10n = AppLocalizations.of(context)!;
      return Center(
        child: Text(
          widget.type != null
              ? l10n.emptyStateByType(widget.type!.name)
              : l10n.emptyStateAll,
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w, vertical: AppSpacing.sm.h),
      itemCount: _savedItems.length,
      itemBuilder: (context, index) {
        final l10n = AppLocalizations.of(context)!;
        final item = _savedItems[index];
        final resourceId = item.id.toString();
        // Bookmarks with unknown metadata (not in catalog either) still need a label.
        final displayTitle = item.title.trim().isNotEmpty ? item.title : l10n.savedResourcesTitle;
        if (_tombstoneIds.contains(resourceId)) {
          return _buildTombstoneCard(item, displayTitle, resourceId, cs, tt, l10n);
        }
        final isSavedDownloaded = _downloadedIds.contains(resourceId);
        final isSavedDownloading = _downloadingIds.contains(resourceId);
        final isRemoved = _removedIds.contains(resourceId);
        return GestureDetector(
          onTap: () => _openItem(item),
          child: Container(
              margin: EdgeInsets.only(bottom: AppSpacing.md.h),
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w, vertical: AppSpacing.md.h),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(
              children: [
                ResourceThumbnail(resource: item, size: 48),
                SizedBox(width: AppSpacing.md.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(displayTitle,
                          style: tt.titleSmall?.copyWith(color: cs.onSurface),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      SizedBox(height: AppSpacing.xs.h),
                      Text(l10n.resourceSubtitle(item.subject, item.grade),
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
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
                ),
                SizedBox(width: AppSpacing.sm.w),
                if (isSavedDownloading)
                  SizedBox(
                    width: 24.w,
                    height: 24.h,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: Icon(
                      isSavedDownloaded ? Icons.check_circle : Icons.download_outlined,
                      color: isSavedDownloaded ? LuminaColors.successGreen : cs.primary,
                    ),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final l10n = AppLocalizations.of(context)!;
                      final downloadService = DownloadService();
                      if (_removedIds.contains(resourceId)) {
                        messenger.showSnackBar(SnackBar(
                          content: Text(l10n.removedFromServerSnackbar),
                          duration: const Duration(seconds: 3),
                        ));
                      } else if (isSavedDownloaded) {
                        await downloadService.deleteDownload(resourceId);
                        if (item.type == ResourceType.kiwix) {
                          var zimId = item.id;
                          if (zimId.startsWith('zim_')) zimId = zimId.substring(4);
                          ZimSyncService.instance.unmarkDownloaded(zimId);
                        }
                        if (mounted) {
                          setState(() => _downloadedIds.remove(resourceId));
                        }
                        messenger.showSnackBar(SnackBar(
                          content: Text(l10n.snackbarDownloadRemoved),
                          duration: const Duration(milliseconds: 600),
                        ));
                      } else {
                        if (item.type == ResourceType.kiwix) {
                          String articleId = item.id;
                          if (articleId.startsWith('zim_')) articleId = articleId.substring(4);
                          await _downloadZimArticle(articleId, title: item.title);
                        } else {
                          final url = item.pdfUrl ?? '/files/$resourceId';
                          final ext = switch (item.type) {
                            ResourceType.videos => '.mp4',
                            _ => '.pdf',
                          };
                          final fileName = '${item.title}$ext';
                          await DownloadQueue().enqueue(resourceId, url, fileName,
                            title: item.title, subject: item.subject,
                            grade: item.grade, type: item.type.name,
                          );
                          if (mounted) setState(() => _pendingIds.add(resourceId));
                        }
                      }
                    },
                  ),
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  icon: Icon(Icons.bookmark_remove, color: cs.error),
                  onPressed: () async {
                    await _toggleSave(item.id);
                    if (mounted) {
                      setState(() {
                        _savedItems.removeWhere((r) => r.id == item.id);
                      });
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
        ),
      ),
    );
  }
}

/// Lists enrolled courses from [CourseService].
class _SavedCoursesTab extends StatefulWidget {
  const _SavedCoursesTab();

  @override
  State<_SavedCoursesTab> createState() => _SavedCoursesTabState();
}

class _SavedCoursesTabState extends State<_SavedCoursesTab> {
  bool _loading = true;
  List<Course> _savedCourses = [];
  List<Course> _unresolvedSaved = [];
  Set<String> _tombstoneCourseIds = {};
  Set<String> _enrolledIds = {};

  @override
  void initState() {
    super.initState();
    _load();
    SavedResourcesPage.refreshNotifier.addListener(_load);
  }

  @override
  void dispose() {
    SavedResourcesPage.refreshNotifier.removeListener(_load);
    super.dispose();
  }

  /// Minimal [Course] from a bookmark row for offline/stale display, when the
  /// cached catalog has no entry. Titles come from the local row only.
  Course _courseFromBookmark(Map<String, dynamic> r) {
    final id = (r['resource_id'] ?? '').toString();
    final title = (r['title'] ?? '').toString();
    return Course(
      id: id,
      title: title.isNotEmpty ? title : id,
      subject: (r['subject'] ?? '').toString(),
      grade: int.tryParse((r['grade'] ?? '').toString()) ?? 0,
      language: 'en',
      published: 0,
    );
  }

  Future<void> _load() async {
    final svc = CourseService();
    await svc.loadEnrolledCourses();
    final enrolled = svc.enrolledCourses;
    List<Map<String, dynamic>> rows = const [];
    try {
      rows = await DBHelper().getBookmarkedResources();
    } catch (_) {}
    final savedRows =
        rows.where((r) => (r['type'] ?? '').toString() == 'course').toList();
    Map<String, Course> catalogById = {};
    try {
      final cached = await svc.getCachedCatalog();
      catalogById = {for (final c in cached) c.id: c};
    } catch (_) {}
    // Course tombstones need a fresh catalog plus a confirming detail 404:
    // never flag while offline or on a stale cache.
    final fresh =
        ConnectivityService().isOnline && CatalogService().isFresh;
    final saved = <Course>[];
    final unresolved = <Course>[];
    final tombstones = <String>{};
    for (final r in savedRows) {
      final id = (r['resource_id'] ?? '').toString();
      if (id.isEmpty) continue;
      final hit = catalogById[id];
      if (hit != null) {
        saved.add(hit);
        continue;
      }
      if (fresh) {
        Map<String, dynamic>? detail;
        try {
          detail = await svc.fetchCourseDetail(id);
        } catch (_) {}
        if (detail == null) {
          tombstones.add(id);
          unresolved.add(_courseFromBookmark(r));
          continue;
        }
        try {
          saved.add(Course.fromJson(detail));
          continue;
        } catch (_) {}
      }
      unresolved.add(_courseFromBookmark(r));
    }
    if (mounted) {
      setState(() {
        _savedCourses = saved;
        _unresolvedSaved = unresolved;
        _tombstoneCourseIds = tombstones;
        _enrolledIds = {for (final e in enrolled) e.course.id};
        _loading = false;
      });
    }
  }

  Future<void> _unsaveCourse(String id) async {
    try {
      await DBHelper().removeBookmark(id);
      unawaited(BookmarkSync.push());
    } catch (_) {}
    SavedResourcesPage.refreshNotifier.value++;
    if (mounted) {
      setState(() {
        _savedCourses.removeWhere((c) => c.id == id);
        _unresolvedSaved.removeWhere((c) => c.id == id);
        _tombstoneCourseIds.remove(id);
      });
    }
  }

  /// Enrolls in a saved-but-unenrolled course via the existing flow.
  Future<void> _enrollSaved(Course course) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    final ok = await CourseService().enroll(course.id);
    if (!mounted) return;
    if (ok) {
      await _load();
      SavedResourcesPage.refreshNotifier.value++;
    } else {
      messenger.showSnackBar(SnackBar(content: Text(l10n.errorNoServerNoCache)));
    }
  }

  void _openCourse(Course course) {
    unawaited(Navigator.push(
      context,
      luminaRoute(builder: (_) => CoursePlayerPage(course: course)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final enrolled = CourseService().enrolledCourses;
    final savedAll = [..._savedCourses, ..._unresolvedSaved];

    if (enrolled.isEmpty && savedAll.isEmpty) {
      return Center(
        child: Text(
          l10n.emptyStateAll,
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: ListView(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w, vertical: AppSpacing.sm.h),
          children: [
            for (final entry in enrolled)
              _buildEnrolledCard(entry.course, entry.progress, cs, tt, l10n),
            if (savedAll.isNotEmpty) ...[
              Padding(
                padding: EdgeInsets.only(top: AppSpacing.md.h, bottom: AppSpacing.sm.h),
                child: Text(l10n.savedCoursesSection,
                    style: tt.titleSmall?.copyWith(
                        color: cs.onSurface, fontWeight: AppSpacing.weightStrong)),
              ),
              for (final course in savedAll) _buildSavedCard(course, cs, tt, l10n),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEnrolledCard(Course course, Map<String, dynamic>? progress,
      ColorScheme cs, TextTheme tt, AppLocalizations l10n) {
    final rawDone = (progress?['completed_count'] as num?)?.toInt() ?? 0;
    final rawTotal = (progress?['total_resources'] as num?)?.toInt() ?? 0;
    final shown = displayProgress(rawDone, rawTotal);
    final completedCount = shown.done;
    final totalResources = shown.total;
    final isCompleted = (progress?['completed'] as num?)?.toInt() == 1;

    return Container(
      margin: EdgeInsets.only(bottom: AppSpacing.md.h),
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w, vertical: AppSpacing.md.h),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 48.w,
            height: 48.h,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Icon(Icons.school, color: cs.primary, size: 24.sp),
          ),
          SizedBox(width: AppSpacing.md.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(course.title,
                    style: tt.titleSmall?.copyWith(color: cs.onSurface),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                SizedBox(height: AppSpacing.xs.h),
                Text(l10n.resourceSubtitle(course.subject, course.grade.toString()),
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                if (totalResources > 0)
                  Text(
                    l10n.browseProgressFormat(completedCount, totalResources),
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          SizedBox(width: AppSpacing.sm.w),
          FilledButton(
            onPressed: () => _openCourse(course),
            child: Text(isCompleted
                ? l10n.coursePlayerCompleted
                : l10n.coursePlayerStart),
          ),
        ],
      ),
    );
  }

  /// Saved-course card resolving a bookmarked id through the cached catalog.
  /// Tap opens the player; unenrolled courses enroll via the existing flow.
  /// Tombstoned rows show the deleted message plus Unsave (and Open when the
  /// course is enrolled locally).
  Widget _buildSavedCard(Course course, ColorScheme cs, TextTheme tt, AppLocalizations l10n) {
    final isTombstone = _tombstoneCourseIds.contains(course.id);
    final isEnrolled = _enrolledIds.contains(course.id);
    return GestureDetector(
      onTap: (isTombstone && !isEnrolled) ? null : () => _openCourse(course),
      child: Container(
        margin: EdgeInsets.only(bottom: AppSpacing.md.h),
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w, vertical: AppSpacing.md.h),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 48.w,
              height: 48.h,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Icon(Icons.school, color: cs.primary, size: 24.sp),
            ),
            SizedBox(width: AppSpacing.md.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(course.title,
                      style: tt.titleSmall?.copyWith(color: cs.onSurface),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  SizedBox(height: AppSpacing.xs.h),
                  Text(
                      isTombstone
                          ? l10n.savedDeletedMessage
                          : l10n.resourceSubtitle(course.subject, course.grade.toString()),
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            SizedBox(width: AppSpacing.sm.w),
            if (isTombstone) ...[
              if (isEnrolled)
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(AppSpacing.touchTarget, AppSpacing.touchTarget),
                  ),
                  onPressed: () => _openCourse(course),
                  child: Text(l10n.savedOpenFile),
                ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: cs.error,
                  minimumSize: const Size(AppSpacing.touchTarget, AppSpacing.touchTarget),
                ),
                onPressed: () => _unsaveCourse(course.id),
                child: Text(l10n.courseUnsave),
              ),
            ] else if (isEnrolled)
              FilledButton(
                onPressed: () => _openCourse(course),
                child: Text(l10n.coursePlayerStart),
              )
            else
              FilledButton(
                onPressed: () => _enrollSaved(course),
                child: Text(l10n.browseEnroll),
              ),
          ],
        ),
      ),
    );
  }
}
