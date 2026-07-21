import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:path_provider/path_provider.dart';
import 'package:edumesh_android/core/models/resource_model.dart';
import 'package:edumesh_android/core/constants/lumina_colors.dart';
import 'package:edumesh_android/core/constants/app_spacing.dart';
import 'package:edumesh_android/core/network/api_client.dart';
import 'package:edumesh_android/shared/services/download_service.dart';
import 'package:edumesh_android/shared/services/download_queue.dart';
import 'package:edumesh_android/shared/services/connectivity_service.dart';
import 'package:edumesh_android/shared/widgets/pdf_viewer_page.dart';
import 'package:edumesh_android/shared/widgets/resource_thumbnail.dart';
import 'package:edumesh_android/shared/widgets/video_player_page.dart';
import 'package:edumesh_android/core/storage/db_helper.dart';
import 'package:edumesh_android/core/services/activity_tracker.dart';
import 'package:edumesh_android/core/services/catalog_service.dart';
import 'package:edumesh_android/core/utils/file_utils.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';

/// A page that lists resources matching a given subject, grade, and type.
///
/// Fetches resources from the server (or from local downloads as fallback),
/// displays them in a scrollable list, and provides download, bookmark, and
/// open actions for each item.
class ResourceDetailPage extends StatefulWidget {
  /// The display title for the resource type (e.g. "Textbooks", "PYQs").
  final String title;

  /// The subject to filter resources by.
  final String subject;

  /// The grade level to filter resources by.
  final String grade;

  /// The resource type identifier (e.g. "textbook", "pyq", "notes", "videos").
  final String resourceType;

  /// Whether the resource is already bookmarked when this page loads.
  final bool isInitiallySaved;

  const ResourceDetailPage({
    super.key,
    required this.title,
    required this.subject,
    required this.grade,
    required this.resourceType,
    this.isInitiallySaved = false,
  });

  /// Creates the state for the [ResourceDetailPage].
  @override
  State<ResourceDetailPage> createState() => _ResourceDetailPageState();
}

class _ResourceDetailPageState extends State<ResourceDetailPage> {
  List<ResourceModel> items = [];
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
      if (mounted) _loadStatus();
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
    // ponytail: throttle DB query to max once per 3s during active downloads.
    _queueThrottle?.cancel();
    _queueThrottle = Timer(const Duration(seconds: 3), () {
      DBHelper().getDownloadedIds().then((ids) {
        if (mounted) setState(() => _downloadedIds = ids);
      });
    });
  }

  Future<void> _loadResources() async {
    try {
      final targetType = _resolveType(widget.resourceType);
      final queryParams = <String, String>{
        'subject': widget.subject,
        'resource_type': targetType,
      };
      if (widget.grade.isNotEmpty) {
        queryParams['grade'] = widget.grade;
      }
      final resp = await ApiClient.get('/resources', queryParameters: queryParams);
      if (!mounted) return;
      final all = (resp.data as List?)?.cast<Map<String, dynamic>>() ?? [];
      setState(() {
        items = all.map((j) => ResourceModel.fromJson(j)).toList();
        _loading = false;
      });
      return;
    } catch (_) { } final targetType = _resolveType(widget.resourceType);
    try {
      final cached = await CatalogService().getCatalog(
        subject: widget.subject,
        grade: widget.grade,
        type: targetType,
      );
      if (cached.isNotEmpty) {
        if (mounted) {
          setState(() {
            items = cached;
            _loading = false;
          });
        }
        return;
      }
    } catch (_) { } try {
      final db = DBHelper();
      final rows = await db.getDownloadedResources();
      if (mounted) {
        setState(() {
          items = rows
            .where((r) =>
              r['subject'] == widget.subject &&
              r['grade'] == widget.grade &&
              r['type'] == targetType)
            .map((r) => ResourceModel(
              id: r['resource_id'] as String? ?? '',
              title: r['title'] as String? ?? '',
              subject: r['subject'] as String? ?? '',
              grade: r['grade'] as String? ?? '',
              type: parseResourceType(r['type'] as String? ?? ''),
              pdfUrl: r['local_path'] as String?,
            ))
            .toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadStatus() async {
    try {
      final dlIds = await DBHelper().getDownloadedIds();
      final pdIds = await DBHelper().getPendingIds();
      final bmIds = await DBHelper().getBookmarkedIds();
      if (mounted) {
        setState(() {
          _downloadedIds = dlIds;
          _pendingIds = pdIds;
          _bookmarkedIds = bmIds;
        });
      }
    } catch (_) { } }

  static String _resolveType(String resourceType) => switch (resourceType) {
    'textbooks' => 'textbook',
    'pyqs' => 'pyq',
    _ => resourceType,
  };

  static Future<bool> _toggleSave(
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
        unawaited(ActivityTracker().logAction('unsave', resourceId: id, metadata: title ?? ''));
        return false;
      }
      await db.upsertBookmark(
        id,
        title ?? '',
        subject ?? '',
        grade ?? '',
        type ?? '',
        pdfUrl: pdfUrl,
      );
      unawaited(ActivityTracker().logAction('save', resourceId: id, metadata: title ?? ''));
      return true;
    } catch (e) {
      debugPrint('Error toggling bookmark: $e');
      return false;
    }
  }

  Widget _buildDownloadButton(ResourceModel item, ColorScheme cs) {
    final resourceId = item.id.toString();
    final isDownloaded = _downloadedIds.contains(resourceId);
    final isPending = _pendingIds.contains(resourceId);
    final queue = DownloadQueue();
    final isActive = queue.active == resourceId;
    final isQueued = !isActive && (queue.contains(resourceId) || isPending);

    if (isActive) {
      return SizedBox(
        width: 24.w,
        height: 24.h,
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
      icon: Icon(
        isDownloaded ? Icons.check_circle : Icons.download_outlined,
        color: isDownloaded ? LuminaColors.successGreen : cs.primary,
      ),
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        final l10n = AppLocalizations.of(context)!;
        if (isDownloaded) {
          await DownloadService().deleteDownload(resourceId);
          if (mounted) {
            setState(() => _downloadedIds.remove(resourceId));
          }
          messenger.showSnackBar(SnackBar(
            content: Text(l10n.snackbarDownloadRemoved),
            duration: const Duration(milliseconds: 600),
          ));
        } else {
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
              messenger.showSnackBar(SnackBar(
                content: Text(l10n.snackbarAddedToQueueOffline),
                duration: const Duration(seconds: 3),
              ));
            }
            return;
          }

          String? sizeLabel;
          try {
            if (url.isNotEmpty) {
              await ApiClient.ensureInitialized();
              final headResp = await ApiClient.dio.head(url);
              final cl = headResp.headers.value('content-length');
              if (cl != null) {
                sizeLabel = formatFileSize(int.tryParse(cl) ?? 0, l10n);
              }
            }
          } catch (_) {
            sizeLabel = l10n.fileSizeUnavailable;
          }
          if (!mounted) return;

          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(l10n.dialogDownloadTitle),
              content: Text(l10n.dialogDownloadContent(fileName, sizeLabel ?? l10n.fileSizeUnknownFallback)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.buttonCancel)),
                TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.dialogDownloadButton)),
              ],
            ),
          );
          if (confirmed != true) return;

          unawaited(DownloadQueue().enqueue(resourceId, url, fileName,
            title: item.title,
            subject: item.subject,
            grade: item.grade,
            type: item.type.name,
            mtime: item.mtime,
          ));
          if (mounted) setState(() => _pendingIds.add(resourceId));
          messenger.showSnackBar(SnackBar(
            content: Text(l10n.snackbarAddedToQueue),
            duration: const Duration(milliseconds: 600),
          ));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(title: Text(l10n.pageTitleDetail(widget.title, widget.subject))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xxl.w),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off_rounded, size: 64.sp, color: cs.onSurfaceVariant),
                        SizedBox(height: AppSpacing.lg.h),
                        Text(l10n.emptyNoResourcesForType(widget.title),
                            style: tt.titleLarge?.copyWith(color: cs.onSurface)),
                        SizedBox(height: AppSpacing.sm.h),
                        Text(l10n.emptyNoResourcesDetail(widget.subject, widget.grade),
                            textAlign: TextAlign.center,
                            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                        SizedBox(height: AppSpacing.section.h),
                        FilledButton.tonalIcon(
                          onPressed: () => setState(() { _loading = true; _loadResources(); }),
                          icon: const Icon(Icons.refresh),
                          label: Text(l10n.emptyRefreshButton),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.all(AppSpacing.xl.w),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isDl = _downloadedIds.contains(item.id);
                    final isOnline = ConnectivityService().isOnline;
                    final isGhost = !isDl && !isOnline;
                    return Card(
                      margin: EdgeInsets.only(bottom: AppSpacing.lg.h),
                      color: isGhost ? cs.surfaceContainerHighest : null,
                      child: Opacity(
                        opacity: isGhost ? 0.5 : 1.0,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InkWell(
                              onTap: () async {
                                if (item.pdfUrl == null) return;
                                if (isGhost) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text(l10n.snackbarNotDownloaded(item.title)),
                                    action: SnackBarAction(label: l10n.snackbarQueueAction, onPressed: () {
                                      final rawUrl = item.pdfUrl;
                                      final url = (rawUrl != null && rawUrl.isNotEmpty) ? rawUrl : '/files/${item.id}';
                                      DownloadQueue().enqueue(item.id, url, '${item.title}.pdf',
                                        title: item.title, subject: item.subject, grade: item.grade,
                                        type: item.type.name, mtime: item.mtime,
                                      );
                                      if (mounted) setState(() => _pendingIds.add(item.id));
                                    }),
                                  ));
                                  return;
                                }
                                String url = item.pdfUrl!;
                                if (isDl) {
                                  final downloads = await DBHelper().getDownloadedResources();
                                  final match = downloads.where((d) => d['resource_id'] == item.id);
                                  if (match.isNotEmpty) {
                                    final storedMtime = (match.first['mtime'] as num?)?.toDouble() ?? 0;
                                    if (item.mtime > storedMtime) {
                                      final tempDir = await getTemporaryDirectory();
                                      final dlPath = '${tempDir.path}/update_${item.id}_${DateTime.now().millisecondsSinceEpoch}.tmp';
                                      try {
                                        await ApiClient.ensureInitialized();
                                        await ApiClient.dio.download(widget.resourceType == 'textbooks' || widget.resourceType == 'pyqs' ? item.pdfUrl! : item.pdfUrl!, dlPath);
                                        final oldPath = match.first['local_path'] as String?;
                                        final newPath = oldPath ?? dlPath;
                                        if (oldPath != null) {
                                          final oldFile = File(oldPath);
                                          if (await oldFile.exists()) await oldFile.delete();
                                          await File(dlPath).rename(oldPath);
                                        }
                                        await DBHelper().insertDownload(item.id, newPath, item.title, item.subject, item.grade, item.type.name, mtime: item.mtime);
                                        url = newPath;
                                      } catch (_) {
                                        final localPath = match.first['local_path'] as String?;
                                        if (localPath != null) url = localPath;
                                      }
                                    } else {
                                      final localPath = match.first['local_path'] as String?;
                                      if (localPath != null) url = localPath;
                                    }
                                  }
                                }
                                if (item.type == ResourceType.videos) {
                                  unawaited(Navigator.of(this.context).push(MaterialPageRoute(
                                    builder: (_) => VideoPlayerPage(
                                      title: item.title,
                                      videoUrl: url,
                                    ),
                                  )));
                                } else {
                                  unawaited(Navigator.of(this.context).push(MaterialPageRoute(
                                    builder: (_) => PdfViewerPage(
                                      title: item.title,
                                      pdfUrl: url,
                                    ),
                                  )));
                                }
                              },
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w, vertical: AppSpacing.sm.h),
                                child: Row(
                                  children: [
                                    ResourceThumbnail(resource: item, size: 48),
                                    SizedBox(width: AppSpacing.md.w),
                                    Expanded(
                                      child: Text(
                                        l10n.resourceSubtitle(item.subject, item.grade),
                                        style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                                      ),
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: Icon(
                                            _bookmarkedIds.contains(item.id) ? Icons.bookmark : Icons.bookmark_border,
                                            color: _bookmarkedIds.contains(item.id) ? cs.primary : cs.onSurfaceVariant,
                                          ),
                                          onPressed: () async {
                                            final saved = await _toggleSave(
                                              item.id,
                                              title: item.title,
                                              subject: item.subject,
                                              grade: item.grade,
                                              type: item.type.name,
                                              pdfUrl: item.pdfUrl,
                                            );
                                            if (mounted) {
                                              setState(() {
                                                if (saved) { _bookmarkedIds.add(item.id); }
                                                else { _bookmarkedIds.remove(item.id); }
                                              });
                                            }
                                          },
                                        ),
                                        const SizedBox(width: AppSpacing.xs),
                                        _buildDownloadButton(item, cs),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}