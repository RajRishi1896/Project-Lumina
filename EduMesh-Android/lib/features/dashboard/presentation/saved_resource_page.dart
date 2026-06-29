import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:edumesh_android/core/models/resource_model.dart';
import 'package:edumesh_android/core/storage/db_helper.dart';
import 'package:edumesh_android/core/utils/file_utils.dart';
import 'package:edumesh_android/shared/services/download_service.dart';
import 'package:edumesh_android/core/constants/lumina_colors.dart';
import 'package:edumesh_android/core/constants/app_spacing.dart';
import 'package:edumesh_android/shared/widgets/pdf_viewer_page.dart';
import 'package:edumesh_android/shared/widgets/video_player_page.dart';
import 'package:edumesh_android/shared/widgets/resource_thumbnail.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';

/// A page that displays the user's bookmarked resources, organised into
/// "All", "Textbooks", "Videos", "PYQs", and "Notes" tabs.
///
/// Each tab shows a list of saved items with thumbnail, download status, and
/// the ability to open or remove the bookmark.
class SavedResourcesPage extends StatelessWidget {
  const SavedResourcesPage({super.key});

  /// Builds the tabbed layout with five [TabBar] tabs and corresponding
  /// [_SavedListByType] content panes.
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.surface,
          elevation: 0,
          title: Text(
            l10n.savedResourcesTitle,
            style: tt.titleMedium?.copyWith(color: cs.onSurface),
          ),
          bottom: TabBar(
            isScrollable: true,
            labelPadding: EdgeInsets.only(right: AppSpacing.xxl.w),
            labelColor: cs.primary,
            unselectedLabelColor: cs.onSurfaceVariant,
            indicatorColor: cs.primary,
            indicatorWeight: 3.0,
            tabs: [
              Tab(text: l10n.tabAll),
              Tab(text: l10n.tabTextbooks),
              Tab(text: l10n.tabVideos),
              Tab(text: l10n.tabPyqs),
              Tab(text: l10n.tabNotes),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _SavedListByType(),
            _SavedListByType(type: ResourceType.textbook),
            _SavedListByType(type: ResourceType.videos),
            _SavedListByType(type: ResourceType.pyq),
            _SavedListByType(type: ResourceType.notes),
          ],
        ),
      ),
    );
  }
}

class _SavedListByType extends StatefulWidget {
  final ResourceType? type;
  const _SavedListByType({this.type});

  @override
  State<_SavedListByType> createState() => _SavedListByTypeState();
}

class _SavedListByTypeState extends State<_SavedListByType> {
  List<ResourceModel> _savedItems = [];
  Set<String> _downloadedIds = {};
  final Set<String> _downloadingIds = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final rows = await DBHelper().getBookmarkedResources();
      final all = rows.map((r) => ResourceModel(
        id: r['resource_id'] as String? ?? '',
        title: r['title'] as String? ?? '',
        subject: r['subject'] as String? ?? '',
        grade: r['grade'] as String? ?? '',
        type: parseResourceType(r['type'] as String? ?? ''),
        pdfUrl: r['pdf_url'] as String?,
      )).toList();
      final items = widget.type != null
          ? all.where((r) => r.type == widget.type!).toList()
          : all;
      final ids = await DBHelper().getDownloadedIds();
      if (mounted) {
        setState(() {
          _savedItems = items;
          _downloadedIds = ids;
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
    if (item.type == ResourceType.videos) {
      unawaited(Navigator.push(context, MaterialPageRoute(
        builder: (_) => VideoPlayerPage(title: item.title, videoUrl: url),
      )));
    } else {
      unawaited(Navigator.push(context, MaterialPageRoute(
        builder: (_) => PdfViewerPage(title: item.title, pdfUrl: url),
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

    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w, vertical: AppSpacing.sm.h),
      itemCount: _savedItems.length,
      itemBuilder: (context, index) {
        final l10n = AppLocalizations.of(context)!;
        final item = _savedItems[index];
        final resourceId = item.id.toString();
        final isSavedDownloaded = _downloadedIds.contains(resourceId);
        final isSavedDownloading = _downloadingIds.contains(resourceId);
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
                      Text(item.title,
                          style: tt.titleSmall?.copyWith(color: cs.onSurface),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      SizedBox(height: AppSpacing.xs.h),
                      Text(l10n.resourceSubtitle(item.subject, item.grade),
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
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
                      if (isSavedDownloaded) {
                        await downloadService.deleteDownload(resourceId);
                        if (mounted) {
                          setState(() => _downloadedIds.remove(resourceId));
                        }
                        messenger.showSnackBar(SnackBar(
                          content: Text(l10n.snackbarDownloadRemoved),
                          duration: const Duration(milliseconds: 600),
                        ));
                      } else {
                        setState(() => _downloadingIds.add(resourceId));
                        try {
                          final url = item.pdfUrl ?? '/files/$resourceId';
                          final fileName = '${item.title}.pdf';
                          final path = await downloadService.downloadAndTrack(
                            resourceId, url, fileName,
                            title: item.title,
                            subject: item.subject,
                            grade: item.grade,
                            type: item.type.name,
                          );
                          if (mounted) {
                            setState(() {
                              _downloadingIds.remove(resourceId);
                              if (path != null) _downloadedIds.add(resourceId);
                            });
                          }
                          if (path != null) {
                            messenger.showSnackBar(SnackBar(
                              content: Text(l10n.snackbarDownloadComplete),
                              duration: const Duration(milliseconds: 600),
                            ));
                          }
                        } catch (e) {
                          debugPrint('Download error: $e');
                          if (mounted) {
                            setState(() => _downloadingIds.remove(resourceId));
                          }
                          messenger.showSnackBar(SnackBar(
                            content: Text(l10n.snackbarDownloadFailed),
                            duration: const Duration(milliseconds: 600),
                          ));
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
    );
  }
}