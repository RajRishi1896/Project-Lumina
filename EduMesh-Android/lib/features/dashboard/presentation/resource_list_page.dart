import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/constants/lumina_colors.dart';
import '../../../core/models/resource_model.dart';
import '../../../core/services/resource_service.dart';
import '../../../core/services/sync_service.dart';
import '../../../shared/services/download_service.dart';
import '../../../shared/widgets/lumina_card.dart';
import 'kiwix_view.dart';
import 'video_view.dart';
import 'pdf_view.dart';

class ResourceListPage extends StatelessWidget {
  final ResourceType type;
  final String title;
  final ResourceService _resourceService = ResourceService();
  final SyncService _syncService = SyncService();

  ResourceListPage({
    super.key,
    required this.type,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: LuminaColors.onSurface,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: LuminaColors.academicTeal),
      ),
      body: FutureBuilder<List<Resource>>(
        future: _resourceService.fetchResources(type),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: LuminaColors.academicTeal));
          }
          if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.library_books_outlined, size: 64.sp, color: Colors.grey.shade300),
                  SizedBox(height: 16.h),
                  Text('There is nothing here', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                ],
              ),
            );
          }
          final resources = snapshot.data!;
          return ListView.separated(
            padding: EdgeInsets.all(24.w),
            itemCount: resources.length,
            separatorBuilder: (_, __) => SizedBox(height: 16.h),
            itemBuilder: (context, index) {
              final resource = resources[index];
              return _ResourceListItem(resource: resource, syncService: _syncService);
            },
          );
        },
      ),
    );
  }
}

class _ResourceListItem extends StatelessWidget {
  final Resource resource;
  final SyncService syncService;

  const _ResourceListItem({required this.resource, required this.syncService});

  void _handleOpen(BuildContext context) {
    // SYNC: Log the opening of a resource
    syncService.logActivity('OPENED_${resource.type.name.toUpperCase()}', resource.id);

    Widget? page;
    switch (resource.type) {
      case ResourceType.kiwix:
        page = KiwixView(initialUrl: resource.url);
        break;
      case ResourceType.khan:
        page = VideoView(url: resource.url, isLocal: resource.isDownloaded);
        break;
      case ResourceType.textbook:
      case ResourceType.pyq:
      case ResourceType.notes:
        page = PdfView(path: resource.url, title: resource.title);
        break;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page!));
  }

  void _handleDownload(BuildContext context) async {
    final service = DownloadService();
    
    try {
      await service.downloadFile(
        resource.url,
        '${resource.id}.file',
        onProgress: (received, total) {},
      );
      
      // SYNC: Log the download completion
      syncService.syncDownloadHistory([resource.id]);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download Complete: ${resource.title}'),
            backgroundColor: LuminaColors.successGreen,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        if (e.toString().contains("STORAGE_FULL")) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Not enough storage on your phone to save this.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Download failed. Check your connection.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LuminaCard(
      onTap: () => _handleOpen(context),
      padding: EdgeInsets.all(16.w),
      borderColor: Colors.grey.shade200,
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(10.w),
            decoration: BoxDecoration(
              color: LuminaColors.academicTeal.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              resource.type == ResourceType.khan ? Icons.play_circle_fill : Icons.description,
              color: LuminaColors.academicTeal,
              size: 24.sp,
            ),
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  resource.title,
                  style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700, color: LuminaColors.onSurface),
                ),
                SizedBox(height: 4.h),
                _StatusIndicator(isDownloaded: resource.isDownloaded),
              ],
            ),
          ),
          IconButton(
            onPressed: resource.isDownloaded ? null : () => _handleDownload(context),
            icon: Icon(
              resource.isDownloaded ? Icons.check_circle : Icons.download_for_offline,
              color: resource.isDownloaded ? LuminaColors.successGreen : LuminaColors.academicTeal,
              size: 26.sp,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  final bool isDownloaded;
  const _StatusIndicator({required this.isDownloaded});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6.w, height: 6.w,
          decoration: BoxDecoration(color: isDownloaded ? LuminaColors.successGreen : LuminaColors.saffron, shape: BoxShape.circle),
        ),
        SizedBox(width: 6.w),
        Text(
          isDownloaded ? 'OFFLINE READY' : 'ON MESH HUB',
          style: TextStyle(color: isDownloaded ? LuminaColors.successGreen : Colors.grey.shade500, fontSize: 10.sp, fontWeight: FontWeight.w800, letterSpacing: 0.5),
        ),
      ],
    );
  }
}
