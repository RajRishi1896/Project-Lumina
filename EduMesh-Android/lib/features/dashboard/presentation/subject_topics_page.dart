import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:edumesh_android/core/constants/app_spacing.dart';
import 'package:edumesh_android/core/constants/lumina_colors.dart';
import 'package:edumesh_android/core/models/resource_model.dart';
import 'package:edumesh_android/core/network/api_client.dart';
import 'package:edumesh_android/core/storage/db_helper.dart';
import 'package:edumesh_android/core/services/catalog_service.dart';
import 'package:edumesh_android/core/utils/file_utils.dart';
import 'package:edumesh_android/shared/services/connectivity_service.dart';
import 'package:edumesh_android/shared/services/download_queue.dart';
import 'package:edumesh_android/shared/services/download_service.dart';
import 'package:edumesh_android/shared/widgets/resource_thumbnail.dart';
import 'package:edumesh_android/shared/widgets/video_player_page.dart';
import 'package:edumesh_android/shared/widgets/pdf_viewer_page.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';
import 'quiz_player_page.dart';
import 'kiwix_view.dart';

/// Shows topics for a subject, or resources directly if no topics exist.
class SubjectTopicsPage extends StatefulWidget {
  final String subject;
  const SubjectTopicsPage({super.key, required this.subject});

  @override
  State<SubjectTopicsPage> createState() => _SubjectTopicsPageState();
}

class _SubjectTopicsPageState extends State<SubjectTopicsPage> {
  List<ResourceModel> _resources = [];
  bool _loading = true;
  Set<String> _downloadedIds = {};
  Set<String> _pendingIds = {};
  Set<String> _bookmarkedIds = {};

  @override
  void initState() {
    super.initState();
    DownloadQueue().addListener(_onQueueChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadResources();
    });
  }

  @override
  void dispose() {
    DownloadQueue().removeListener(_onQueueChanged);
    super.dispose();
  }

  Timer? _queueThrottle;

  void _onQueueChanged() {
    if (mounted) setState(() {});
    _queueThrottle?.cancel();
    _queueThrottle = Timer(const Duration(seconds: 3), () {
      DBHelper().getDownloadedIds().then((ids) {
        if (mounted) setState(() => _downloadedIds = ids);
      });
    });
  }

  Future<void> _loadResources() async {
    final ids = await DBHelper().getDownloadedIds();
    final pdIds = await DBHelper().getPendingIds();
    final bmIds = await DBHelper().getBookmarkedIds();
    if (mounted) setState(() { _downloadedIds = ids; _pendingIds = pdIds; _bookmarkedIds = bmIds; });

    try {
      final resp = await ApiClient.get('/resources', queryParameters: {'subject': widget.subject});
      if (mounted && resp.statusCode == 200 && resp.data is List) {
        final all = (resp.data as List).cast<Map<String, dynamic>>();
        setState(() {
          _resources = all.map((j) => ResourceModel.fromJson(j)).toList();
          _loading = false;
        });
        return;
      }
    } catch (_) {}

    try {
      final cached = await CatalogService().getCatalog(subject: widget.subject);
      if (cached.isNotEmpty && mounted) {
        setState(() {
          _resources = cached;
          _loading = false;
        });
        return;
      }
    } catch (_) {}

    try {
      final db = DBHelper();
      final rows = await db.getDownloadedResources();
      final filtered = rows.where((r) {
        if (widget.subject == 'General') {
          return r['subject'] == 'General' || r['grade'] == 'General';
        }
        return r['subject'] == widget.subject;
      })
          .map((r) => ResourceModel(
                id: r['resource_id'] as String? ?? '',
                title: r['title'] as String? ?? '',
                subject: r['subject'] as String? ?? '',
                grade: r['grade'] as String? ?? '',
                type: parseResourceType(r['type'] as String? ?? ''),
                pdfUrl: r['local_path'] as String?,
              ))
          .toList();
      if (mounted) setState(() { _resources = filtered; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openResource(ResourceModel item) async {
    if (item.type == ResourceType.videos) {
      final url = item.pdfUrl ?? '/files/${item.id}';
      unawaited(Navigator.push(context, MaterialPageRoute(
        builder: (_) => VideoPlayerPage(title: item.title, videoUrl: url, subject: item.subject),
      )));
    } else if (item.type == ResourceType.quiz) {
      unawaited(Navigator.push(context, MaterialPageRoute(
        builder: (_) => QuizPlayerPage.fromResource(item),
      )));
    } else if (item.type == ResourceType.kiwix) {
      String? html;
      try {
        final response = await ApiClient.get('/zim/page', queryParameters: {
          'article_id': item.id,
        }).timeout(const Duration(seconds: 8));
        html = response.data?['html']?.toString();
      } catch (_) {}
      if (!mounted) return;
      if (html != null && html.isNotEmpty) {
        unawaited(Navigator.push(context, MaterialPageRoute(
          builder: (_) => KiwixView(initialHtml: html, title: item.title, baseUrl: ApiClient.baseUrl, subject: item.subject),
        )));
      }
    } else {
      final url = item.pdfUrl ?? '/files/${item.id}';
      unawaited(Navigator.push(context, MaterialPageRoute(
        builder: (_) => PdfViewerPage(title: item.title, pdfUrl: url, subject: item.subject),
      )));
    }
  }

  Map<String, List<ResourceModel>> _groupByTopic() {
    final map = <String, List<ResourceModel>>{};
    final offline = !ConnectivityService().isOnline;
    for (final r in _resources) {
      final key = r.topicName.isNotEmpty ? r.topicName : '';
      map.putIfAbsent(key, () => []).add(r);
    }
    if (offline) {
      for (final entry in map.values) {
        entry.sort((a, b) {
          final aDl = _downloadedIds.contains(a.id);
          final bDl = _downloadedIds.contains(b.id);
          if (aDl == bDl) return a.title.compareTo(b.title);
          return aDl ? -1 : 1;
        });
      }
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: cs.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.subject, style: tt.titleLarge?.copyWith(color: cs.onSurface)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _resources.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.folder_open, size: 64.sp, color: cs.onSurfaceVariant),
                      SizedBox(height: AppSpacing.lg.h),
                      Text(l10n.emptyNoResources, style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                )
              : _buildBody(),
    );
  }

  Widget _buildDownloadButton(ResourceModel item, ColorScheme cs) {
    final l10n = AppLocalizations.of(context)!;
    final resourceId = item.id.toString();
    final isDownloaded = _downloadedIds.contains(resourceId);
    final isPending = _pendingIds.contains(resourceId);
    final queue = DownloadQueue();
    final isActive = queue.active == resourceId;
    final isQueued = !isActive && (queue.contains(resourceId) || isPending);

    if (isActive) {
      return SizedBox(
        width: 24.w, height: 24.h,
        child: const CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (isQueued) {
      return IconButton(
        icon: Icon(Icons.hourglass_bottom, color: cs.onSurfaceVariant),
        onPressed: null,
      );
    }
    return IconButton(
      tooltip: l10n.dialogDownloadTitle,
      icon: Icon(
        isDownloaded ? Icons.check_circle : Icons.download_outlined,
        color: isDownloaded ? LuminaColors.successGreen : cs.primary,
      ),
      onPressed: () async {
        if (isDownloaded) {
          await DownloadService().deleteDownload(resourceId);
          if (mounted) setState(() => _downloadedIds.remove(resourceId));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(AppLocalizations.of(context)!.snackbarDownloadRemoved),
              duration: const Duration(milliseconds: 600),
            ));
          }
          return;
        }
        final rawUrl = item.pdfUrl;
        final url = (rawUrl != null && rawUrl.isNotEmpty) ? rawUrl : '/files/$resourceId';
        final ext = url.contains('.') ? '.${url.split('.').last.split('?').first}' : '.pdf';
        final fileName = '${item.title}$ext';
        final isOnline = ConnectivityService().isOnline;
        if (!isOnline) {
          await DownloadQueue().enqueue(resourceId, url, fileName,
            title: item.title, subject: item.subject, grade: item.grade,
            type: item.type.name, mtime: item.mtime,
          );
          if (mounted) {
            setState(() => _pendingIds.add(resourceId));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(AppLocalizations.of(context)!.snackbarAddedToQueueOffline),
              duration: const Duration(seconds: 3),
            ));
          }
          return;
        }
        // Online: enqueue directly (no confirmation dialog for subject topics).
        unawaited(DownloadQueue().enqueue(resourceId, url, fileName,
          title: item.title, subject: item.subject, grade: item.grade,
          type: item.type.name, mtime: item.mtime,
        ));
        if (mounted) {
          setState(() => _pendingIds.add(resourceId));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!.snackbarAddedToQueue),
            duration: const Duration(milliseconds: 600),
          ));
        }
      },
    );
  }

  Future<void> _toggleBookmark(ResourceModel item) async {
    final id = item.id.toString();
    final db = DBHelper();
    final bookmarked = await db.getBookmarkedIds();
    if (bookmarked.contains(id)) {
      await db.removeBookmark(id);
    } else {
      await db.upsertBookmark(id, item.title, item.subject, item.grade, item.type.name, pdfUrl: item.pdfUrl);
    }
    final updated = await db.getBookmarkedIds();
    if (mounted) setState(() => _bookmarkedIds = updated);
    unawaited(_syncBookmarksToServer());
  }

  static Future<void> _syncBookmarksToServer() async {
    try {
      final db = DBHelper();
      final bookmarks = await db.getBookmarkedResources();
      final items = bookmarks.map((b) => {
        'resource_id': b['resource_id']?.toString() ?? '',
        'title': b['title']?.toString() ?? '',
        'subject': b['subject']?.toString() ?? '',
        'grade': b['grade']?.toString() ?? '',
        'resource_type': b['type']?.toString() ?? '',
      }).toList();
      await ApiClient.post('/student/sync-bookmarks', data: {'bookmarks': items});
    } catch (_) {}
  }

  Widget _buildBody() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final grouped = _groupByTopic();
    final isOffline = !ConnectivityService().isOnline;

    final widgets = <Widget>[];
    final entries = grouped.entries.toList();
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (entry.key.isEmpty) {
        for (final item in entry.value) {
          final isOfflineUnavailable = isOffline && !_downloadedIds.contains(item.id);
          widgets.add(
            Opacity(
              opacity: isOfflineUnavailable ? 0.45 : 1.0,
              child: Card(
                color: isOfflineUnavailable ? cs.surfaceContainerHighest : null,
                margin: EdgeInsets.only(bottom: AppSpacing.sm.h),
                child: ListTile(
                  leading: ResourceThumbnail(resource: item, size: 40),
                  title: Text(item.title,
                      style: tt.titleSmall?.copyWith(color: cs.onSurface),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  subtitle: Text(item.grade,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: AppLocalizations.of(context)!.bottomNavSaved,
                        icon: Icon(
                          _bookmarkedIds.contains(item.id.toString()) ? Icons.bookmark : Icons.bookmark_border,
                          color: _bookmarkedIds.contains(item.id.toString()) ? cs.primary : cs.onSurfaceVariant,
                        ),
                        onPressed: () => _toggleBookmark(item),
                      ),
                      _buildDownloadButton(item, cs),
                      Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                    ],
                  ),
                  onTap: () => _openResource(item),
                ),
              ),
            ),
          );
        }
        continue;
      }
      widgets.add(
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : AppSpacing.lg.h, bottom: AppSpacing.sm.h),
          child: Text(entry.key,
              style: tt.titleSmall?.copyWith(
                  color: cs.onSurface, fontWeight: AppSpacing.weightStrong)),
        ),
      );
      for (final item in entry.value) {
        final isOfflineUnavailable = isOffline && !_downloadedIds.contains(item.id);
        widgets.add(
          Opacity(
            opacity: isOfflineUnavailable ? 0.45 : 1.0,
            child: Card(
              color: isOfflineUnavailable ? cs.surfaceContainerHighest : null,
              margin: EdgeInsets.only(bottom: AppSpacing.sm.h),
              child: ListTile(
                leading: ResourceThumbnail(resource: item, size: 40),
                title: Text(item.title,
                    style: tt.titleSmall?.copyWith(color: cs.onSurface),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                subtitle: Text(item.grade,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        _bookmarkedIds.contains(item.id.toString()) ? Icons.bookmark : Icons.bookmark_border,
                        color: _bookmarkedIds.contains(item.id.toString()) ? cs.primary : cs.onSurfaceVariant,
                      ),
                      onPressed: () => _toggleBookmark(item),
                    ),
                    _buildDownloadButton(item, cs),
                    Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                  ],
                ),
                  onTap: () => _openResource(item),
              ),
            ),
          ),
        );
      }
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: ListView.builder(
      padding: EdgeInsets.all(AppSpacing.xl.w),
      itemCount: widgets.length,
      itemBuilder: (_, i) => widgets[i],
        ),
      ),
    );
  }

}
