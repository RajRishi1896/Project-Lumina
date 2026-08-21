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
import 'package:edumesh_android/shared/services/share_server.dart';
import 'package:edumesh_android/shared/services/connectivity_service.dart';
import 'package:edumesh_android/shared/widgets/pdf_viewer_page.dart';
import 'package:edumesh_android/shared/widgets/resource_thumbnail.dart';
import 'package:edumesh_android/shared/widgets/video_player_page.dart';
import 'package:edumesh_android/features/dashboard/presentation/quiz_player_page.dart';
import 'package:edumesh_android/features/dashboard/presentation/kiwix_view.dart';
import 'package:edumesh_android/core/storage/db_helper.dart';
import 'package:edumesh_android/core/services/activity_tracker.dart';
import 'package:edumesh_android/core/services/catalog_service.dart';
import 'package:edumesh_android/core/utils/file_utils.dart';
import 'package:edumesh_android/core/services/recent_resources.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';

/// A page that lists resources matching a given subject, grade, and type.
///
/// Fetches resources from the server (or from local downloads as fallback),
/// displays them in a scrollable list, and provides download, bookmark, and
/// open actions for each item.
class ResourceDetailPage extends StatefulWidget {
  /// The display title for the resource type (e.g. "Textbooks", "PYQs").
  final String title;

  final String subject;

  final String grade;

  /// The resource type identifier (e.g. "textbook", "pyq", "notes", "videos").
  final String resourceType;

  final bool isInitiallySaved;

  /// If set, fetch this specific resource by ID instead of filtering by subject/grade/type.
  final String? resourceId;

  const ResourceDetailPage({
    super.key,
    required this.title,
    required this.subject,
    required this.grade,
    required this.resourceType,
    this.isInitiallySaved = false,
    this.resourceId,
  });

  /// Creates the state for the [ResourceDetailPage].
  @override
  State<ResourceDetailPage> createState() => _ResourceDetailPageState();
}

class _ResourceDetailPageState extends State<ResourceDetailPage> {
  List<ResourceModel> items = [];
  bool _loading = true;
  Set<String> _downloadedIds = {};
  Set<String> _removedIds = {};
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
    _queueThrottle?.cancel();
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
    if (widget.resourceId != null && widget.resourceId!.isNotEmpty) {
      try {
        final resp = await ApiClient.get('/resources/${widget.resourceId}');
        if (!mounted) return;
        final data = resp.data as Map<String, dynamic>?;
        if (data != null) {
          final resource = ResourceModel.fromJson(data);
          setState(() { items = [resource]; _loading = false; });
          unawaited(RecentResources.record(widget.resourceId!, resource.title, resource.type.name));
          return;
        }
      } catch (_) {}
      // Fallback to local DB
      try {
        final db = DBHelper();
        final r = await db.getDownloadedResource(widget.resourceId!);
        if (r != null && mounted) {
          setState(() {
            items = [ResourceModel(
              id: r['resource_id'] as String? ?? '',
              title: r['title'] as String? ?? '',
              subject: r['subject'] as String? ?? '',
              grade: r['grade'] as String? ?? '',
              type: parseResourceType(r['type'] as String? ?? ''),
              pdfUrl: r['local_path'] as String?,
            )];
            _loading = false;
          });
          return;
        }
      } catch (_) {}
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final targetType = _resolveType(widget.resourceType);
      final queryParams = <String, String>{
        'resource_type': targetType,
      };
      if (widget.subject.isNotEmpty) {
        queryParams['subject'] = widget.subject;
      }
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
      final rmIds = await DBHelper().getRemovedDownloadIds();
      if (mounted) {
        setState(() {
          _downloadedIds = dlIds;
          _pendingIds = pdIds;
          _bookmarkedIds = bmIds;
          _removedIds = rmIds;
        });
      }
    } catch (_) { } }

  static bool _isServerUrl(String? url) =>
      url != null && url.isNotEmpty && (url.startsWith('http://') || url.startsWith('https://') || url.startsWith('/files/'));

  static String _resolveType(String resourceType) => switch (resourceType) {
    'textbooks' => 'textbook',
    'pyqs' => 'pyq',
    'khan' => 'videos',
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
        _syncBookmarksToServer();
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
      _syncBookmarksToServer();
      return true;
    } catch (e) {
      debugPrint('Error toggling bookmark: $e');
      return false;
    }
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

  /// Copies a view-time cached PDF (from [PdfViewerPage]'s temp cache) into
  /// the downloads folder and records it as a download. Used when a ghost
  /// resource was previously viewed online: the cache becomes a real offline
  /// download with no server connection. Returns false when no cache exists.
  Future<bool> _promoteCachedPdf(ResourceModel item, String resourceId) async {
    final rawUrl = item.pdfUrl;
    if (rawUrl == null || rawUrl.isEmpty) return false;
    final key = rawUrl.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final cacheFile = File('${(await getTemporaryDirectory()).path}/pdf_cache_$key');
    if (!await cacheFile.exists()) return false;
    final ext = rawUrl.contains('.') ? '.${rawUrl.split('.').last.split('?').first}' : '.pdf';
    final dest = File('${(await getApplicationDocumentsDirectory()).path}/$resourceId$ext');
    await cacheFile.copy(dest.path);
    await DBHelper().insertDownload(resourceId, dest.path, item.title, item.subject, item.grade, item.type.name, mtime: item.mtime);
    return true;
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
      tooltip: l10n.dialogDownloadTitle,
      icon: Icon(
        isDownloaded ? Icons.check_circle : Icons.download_outlined,
        color: isDownloaded ? LuminaColors.successGreen : cs.primary,
      ),
      onPressed: () async {
        try {
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
            final onlineNow = ConnectivityService().isOnline;
            if (onlineNow) {
              final peerRawUrl = item.pdfUrl;
              final peerUrl = _isServerUrl(peerRawUrl) ? peerRawUrl! : '/files/$resourceId';
              final peerExt = peerUrl.contains('.') ? '.${peerUrl.split('.').last.split('?').first}' : '.pdf';
              final peerFileName = '${item.title}$peerExt';
              messenger.showSnackBar(SnackBar(
                content: Text(l10n.shareFindingDevices),
                duration: const Duration(milliseconds: 2500),
              ));
              final peerPath = await ShareServer().discoverAndDownload(
                item,
                peerFileName,
                subject: item.subject,
                grade: item.grade,
                type: item.type.name,
                onPeerFound: (name) {
                  if (mounted) setState(() => _pendingIds.add(resourceId));
                  messenger.hideCurrentSnackBar();
                  messenger.showSnackBar(SnackBar(
                    content: Text(l10n.shareDownloadingFrom(name)),
                    duration: const Duration(seconds: 3),
                  ));
                },
              );
              if (peerPath != null) {
                if (mounted) {
                  setState(() {
                    _pendingIds.remove(resourceId);
                    _downloadedIds.add(resourceId);
                  });
                }
                messenger.showSnackBar(SnackBar(
                  content: Text(l10n.snackbarDownloadComplete),
                  duration: const Duration(milliseconds: 600),
                ));
                return;
              }
              messenger.hideCurrentSnackBar();
            }

            final rawUrl = item.pdfUrl;
            final url = _isServerUrl(rawUrl) ? rawUrl! : '/files/$resourceId';
            final ext = url.contains('.') ? '.${url.split('.').last.split('?').first}' : '.pdf';
            final fileName = '${item.title}$ext';

            final isOnline = ConnectivityService().isOnline;
            if (!isOnline) {
              final promoted = await _promoteCachedPdf(item, resourceId);
              if (promoted) {
                if (mounted) {
                  setState(() {
                    _pendingIds.remove(resourceId);
                    _downloadedIds.add(resourceId);
                  });
                  messenger.showSnackBar(SnackBar(
                    content: Text(l10n.snackbarDownloadComplete),
                    duration: const Duration(milliseconds: 600),
                  ));
                }
                return;
              }
              try {
                await DownloadQueue().enqueue(resourceId, url, fileName,
                  title: item.title, subject: item.subject, grade: item.grade,
                  type: item.type.name, mtime: item.mtime,
                );
              } catch (_) {}
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
            ).catchError((_) {}));
            if (mounted) setState(() => _pendingIds.add(resourceId));
            messenger.showSnackBar(SnackBar(
              content: Text(l10n.snackbarAddedToQueue),
              duration: const Duration(milliseconds: 600),
            ));
          }
        } catch (e, st) {
          debugPrint('Download button crash: $e\n$st');
          if (mounted) {
            final l10n = AppLocalizations.of(context)!;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(l10n.snackbarDownloadFailed),
              duration: const Duration(seconds: 3),
            ));
          }
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
      appBar: AppBar(
        title: Text(l10n.pageTitleDetail(widget.title, widget.subject)),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
      ),
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
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
                    child: ListView.builder(
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
                                if (isGhost) {
                                  if (!mounted) return;
                                  final ghostUrl = _isServerUrl(item.pdfUrl) ? item.pdfUrl! : '/files/${item.id}';
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text(l10n.snackbarNotDownloaded(item.title)),
                                    action: SnackBarAction(label: l10n.snackbarQueueAction, onPressed: () {
                                      DownloadQueue().enqueue(item.id, ghostUrl, '${item.title}${ghostUrl.contains('.') ? '.${ghostUrl.split('.').last.split('?').first}' : '.pdf'}',
                                        title: item.title, subject: item.subject, grade: item.grade,
                                        type: item.type.name, mtime: item.mtime,
                                      );
                                      if (mounted) setState(() => _pendingIds.add(item.id));
                                    }),
                                  ));
                                  return;
                                }
                                if (item.type == ResourceType.quiz) {
                                  unawaited(RecentResources.record(item.id.toString(), item.title, item.type.name));
                                  unawaited(ActivityTracker().logAction('view', resourceId: item.id.toString(), metadata: item.title));
                                  unawaited(Navigator.of(this.context).push(MaterialPageRoute(
                                    builder: (_) => QuizPlayerPage.fromResource(item),
                                  )));
                                  return;
                                }
                                if (item.type == ResourceType.kiwix) {
                                  String? html;
                                  try {
                                    final response = await ApiClient.get('/zim/page', queryParameters: {
                                      'article_id': item.id,
                                    }).timeout(const Duration(seconds: 8));
                                    html = response.data?['html']?.toString();
                                  } catch (_) {}
                                  if (!mounted) return;
                                  if (html != null && html.isNotEmpty) {
                                    unawaited(RecentResources.record(item.id.toString(), item.title, item.type.name));
                                    unawaited(ActivityTracker().logAction('view', resourceId: item.id.toString(), metadata: item.title));
                                    unawaited(Navigator.of(this.context).push(MaterialPageRoute(
                                      builder: (_) => KiwixView(initialHtml: html, title: item.title, baseUrl: ApiClient.baseUrl),
                                    )));
                                  }
                                  return;
                                }
                                if (item.type == ResourceType.videos) {
                                  final rawUrl = item.pdfUrl;
                                  final url = _isServerUrl(rawUrl) ? rawUrl! : '/files/${item.id}';
                                  if (!mounted) return;
                                  unawaited(RecentResources.record(item.id.toString(), item.title, item.type.name));
                                  unawaited(ActivityTracker().logAction('view', resourceId: item.id.toString(), metadata: item.title));
                                  unawaited(Navigator.of(this.context).push(MaterialPageRoute(
                                    builder: (_) => VideoPlayerPage(
                                      title: item.title,
                                      videoUrl: url,
                                      subject: item.subject,
                                    ),
                                  )));
                                  return;
                                }
                                if (item.pdfUrl == null || item.pdfUrl!.isEmpty) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                      content: Text(l10n.fileNotAvailable),
                                    ));
                                  }
                                  return;
                                }
                                String url = item.pdfUrl!;
                                if (isDl) {
                                  try {
                                    final downloads = await DBHelper().getDownloadedResources();
                                    final match = downloads.where((d) => d['resource_id'] == item.id);
                                    if (match.isNotEmpty) {
                                      final storedMtime = (match.first['mtime'] as num?)?.toDouble() ?? 0;
                                      final serverRemoved = (match.first['server_removed'] as num? ?? 0) == 1;
                                      if (item.mtime > storedMtime && !serverRemoved) {
                                        final tempDir = await getTemporaryDirectory();
                                        final dlPath = '${tempDir.path}/update_${item.id}_${DateTime.now().millisecondsSinceEpoch}.tmp';
                                        try {
                                          await ApiClient.ensureInitialized();
                                          await ApiClient.dio.download(item.pdfUrl!, dlPath);
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
                                  } catch (_) {
                                    // DB error, will open from server URL
                                  }
                                }
                                if (!mounted) return;
                                unawaited(RecentResources.record(item.id.toString(), item.title, item.type.name));
                                unawaited(ActivityTracker().logAction('view', resourceId: item.id.toString(), metadata: item.title));
                                unawaited(Navigator.of(this.context).push(MaterialPageRoute(
                                  builder: (_) => PdfViewerPage(
                                    title: item.title,
                                    pdfUrl: url,
                                    subject: item.subject,
                                  ),
                                )));
                              },
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w, vertical: AppSpacing.sm.h),
                                child: Row(
                                  children: [
                                    ResourceThumbnail(resource: item, size: 48),
                                    SizedBox(width: AppSpacing.md.w),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            l10n.resourceSubtitle(item.subject, item.grade),
                                            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                                          ),
                                          if (_removedIds.contains(item.id)) ...[
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
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: l10n.bottomNavSaved,
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
                  ),
                ),
    );
  }
}
