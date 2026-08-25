import 'dart:async';
import 'package:edumesh_android/core/navigation/lumina_transitions.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:edumesh_android/core/models/resource_model.dart';
import 'package:edumesh_android/core/services/course_service.dart';
import 'package:edumesh_android/core/storage/db_helper.dart';
import 'package:edumesh_android/core/utils/file_utils.dart';
import 'package:edumesh_android/shared/services/download_service.dart';
import 'package:edumesh_android/shared/services/download_queue.dart';
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

/// A page that displays the user's bookmarked resources, organised into
/// tabs for each resource type plus enrolled courses.
class SavedResourcesPage extends StatelessWidget {
  const SavedResourcesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;

    return DefaultTabController(
      length: 8,
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.surface,
          foregroundColor: cs.onSurface,
          elevation: 0,
          title: Text(
            l10n.savedResourcesTitle,
            style: tt.titleMedium?.copyWith(color: cs.onSurface),
          ),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: cs.primary,
            unselectedLabelColor: cs.onSurfaceVariant,
            indicatorColor: cs.primary,
            indicatorWeight: 3.0,
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
  final Set<String> _downloadingIds = {};
  final Set<String> _pendingIds = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final db = DBHelper();
      final bookmarkRows = await db.getBookmarkedResources();
      final downloadRows = await db.getDownloadedResources();
      final zimRows = await db.getDownloadedZimArticles();

      // Merge bookmarks + downloads + ZIM articles, dedup by resource_id.
      final Map<String, ResourceModel> merged = {};

      for (final r in bookmarkRows) {
        final id = r['resource_id'] as String? ?? '';
        if (id.isEmpty) continue;
        merged[id] = ResourceModel(
          id: id,
          title: r['title'] as String? ?? '',
          subject: r['subject'] as String? ?? '',
          grade: r['grade'] as String? ?? '',
          type: parseResourceType(r['type'] as String? ?? ''),
          pdfUrl: r['pdf_url'] as String?,
        );
      }

      for (final r in downloadRows) {
        final id = r['resource_id'] as String? ?? '';
        if (id.isEmpty || merged.containsKey(id)) continue;
        merged[id] = ResourceModel(
          id: id,
          title: r['title'] as String? ?? '',
          subject: r['subject'] as String? ?? '',
          grade: r['grade'] as String? ?? '',
          type: parseResourceType(r['type'] as String? ?? ''),
        );
      }

      for (final r in zimRows) {
        final id = r['resource_id'] as String? ?? '';
        if (id.isEmpty || merged.containsKey(id)) continue;
        merged[id] = ResourceModel(
          id: id,
          title: r['title'] as String? ?? '',
          subject: r['subject'] as String? ?? '',
          grade: '',
          type: ResourceType.kiwix,
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
      final items = widget.type != null
          ? all.where((r) => r.type == widget.type!).toList()
          : all;
      final ids = await db.getDownloadedIds();
      final removedIds = downloadRows
          .where((r) => (r['server_removed'] as num? ?? 0) == 1)
          .map((r) => r['resource_id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      if (mounted) {
        setState(() {
          _savedItems = items;
          _downloadedIds = ids;
          _removedIds = removedIds;
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
        return false;
      }
      await db.upsertBookmark(id, '', '', '', '');
      return true;
    } catch (e) {
      debugPrint('Error toggling bookmark: $e');
      return false;
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
      // Same fallback order as browse_page: local file -> legacy prefs -> network.
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
          final response = await ApiClient.get('/zim/page', queryParameters: {
            'article_id': articleId,
          }).timeout(const Duration(seconds: 8));
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
                        if (mounted) {
                          setState(() => _downloadedIds.remove(resourceId));
                        }
                        messenger.showSnackBar(SnackBar(
                          content: Text(l10n.snackbarDownloadRemoved),
                          duration: const Duration(milliseconds: 600),
                        ));
                      } else {
                        final url = item.pdfUrl ?? '/files/$resourceId';
                        final ext = switch (item.type) {
                          ResourceType.videos => '.mp4',
                          ResourceType.kiwix => '.html',
                          _ => '.pdf',
                        };
                        final fileName = '${item.title}$ext';
                        await DownloadQueue().enqueue(resourceId, url, fileName,
                          title: item.title, subject: item.subject,
                          grade: item.grade, type: item.type.name,
                        );
                        if (mounted) setState(() => _pendingIds.add(resourceId));
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = CourseService();
    await svc.loadEnrolledCourses();
    if (mounted) setState(() => _loading = false);
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

    if (enrolled.isEmpty) {
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
        child: ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w, vertical: AppSpacing.sm.h),
      itemCount: enrolled.length,
      itemBuilder: (context, index) {
        final entry = enrolled[index];
        final course = entry.course;
        final progress = entry.progress;
        final completedCount = (progress?['completed_count'] as num?)?.toInt() ?? 0;
        final totalResources = (progress?['total_resources'] as num?)?.toInt() ?? 0;
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
                        '$completedCount/$totalResources',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              SizedBox(width: AppSpacing.sm.w),
              FilledButton(
                onPressed: () {
                  unawaited(Navigator.push(
                    context,
                    luminaRoute(
                      builder: (_) => CoursePlayerPage(course: course),
                    ),
                  ));
                },
                child: Text(isCompleted
                    ? l10n.coursePlayerCompleted
                    : l10n.coursePlayerStart),
              ),
            ],
          ),
        );
      },
        ),
      ),
    );
  }
}
