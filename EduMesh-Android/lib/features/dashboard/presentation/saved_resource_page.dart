import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:edumesh_android/core/models/resource_model.dart';
import 'package:edumesh_android/core/storage/db_helper.dart';
import 'package:edumesh_android/shared/services/save_resource_service.dart';
import 'package:edumesh_android/shared/services/download_service.dart';
import 'package:edumesh_android/core/constants/lumina_colors.dart';
import 'package:edumesh_android/core/constants/app_spacing.dart';
import 'package:edumesh_android/shared/widgets/pdf_viewer_page.dart';
import 'package:edumesh_android/shared/widgets/video_player_page.dart';
import 'package:edumesh_android/shared/widgets/resource_thumbnail.dart';

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

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.surface,
          elevation: 0,
          title: Text(
            "Saved Resources",
            style: TextStyle(color: cs.onSurface, fontWeight: AppSpacing.weightStrong),
          ),
          bottom: TabBar(
            isScrollable: true,
            labelPadding: EdgeInsets.only(right: AppSpacing.xxl.w),
            labelColor: cs.primary,
            unselectedLabelColor: cs.onSurfaceVariant,
            indicatorColor: cs.primary,
            indicatorWeight: 3.0,
            tabs: const [
              Tab(text: "All"),
              Tab(text: "Textbooks"),
              Tab(text: "Videos"),
              Tab(text: "PYQs"),
              Tab(text: "Notes"),
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
      final items = widget.type != null
          ? await SaveResourceService.getSavedByType(widget.type!)
          : await SaveResourceService.getAllSavedResourceModels();
      final ids = await DownloadService().getAllDownloadedIds();
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
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => VideoPlayerPage(title: item.title, videoUrl: url),
      ));
    } else {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => PdfViewerPage(title: item.title, pdfUrl: url),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_savedItems.isEmpty) {
      return Center(
        child: Text(
          widget.type != null
              ? "No saved ${widget.type!.name}s found."
              : "No saved resources yet.",
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      itemCount: _savedItems.length,
      itemBuilder: (context, index) {
        final item = _savedItems[index];
        final resourceId = item.id.toString();
        final isSavedDownloaded = _downloadedIds.contains(resourceId);
        final isSavedDownloading = _downloadingIds.contains(resourceId);
        return GestureDetector(
          onTap: () => _openItem(item),
          child: Container(
            margin: EdgeInsets.only(bottom: 10.h),
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(
              children: [
                ResourceThumbnail(resource: item, size: 48),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(item.title,
                          style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      SizedBox(height: 4.h),
                      Text("${item.subject} • ${item.grade}",
                          style: TextStyle(
                              fontSize: 12.sp, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                SizedBox(width: 8.w),
                if (isSavedDownloading)
                  SizedBox(
                    width: 24.w,
                    height: 24.h,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: Icon(
                      isSavedDownloaded ? Icons.check_circle : Icons.download_outlined,
                      color: isSavedDownloaded ? LuminaColors.successGreen : cs.primary,
                    ),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final downloadService = DownloadService();
                      if (isSavedDownloaded) {
                        await downloadService.deleteDownload(resourceId);
                        if (mounted) {
                          setState(() => _downloadedIds.remove(resourceId));
                        }
                        messenger.showSnackBar(SnackBar(
                          content: const Text("Download removed"),
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
                              content: const Text("Download complete"),
                              duration: const Duration(milliseconds: 600),
                            ));
                          }
                        } catch (e) {
                          debugPrint("Download error: $e");
                          if (mounted) {
                            setState(() => _downloadingIds.remove(resourceId));
                          }
                          messenger.showSnackBar(SnackBar(
                            content: const Text("Download failed"),
                            duration: const Duration(milliseconds: 600),
                          ));
                        }
                      }
                    },
                  ),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(Icons.bookmark_remove, color: cs.error),
                  onPressed: () async {
                    await SaveResourceService.toggleSaveStatus(item.id);
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