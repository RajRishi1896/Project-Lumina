import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/constants/lumina_colors.dart';
import '../../../core/models/resource_model.dart';
import '../../../shared/services/mock_data_service.dart';
import '../../../shared/services/download_service.dart';
import '../../../shared/widgets/lumina_card.dart';
import 'kiwix_view.dart';
import 'video_view.dart';
import 'pdf_view.dart';

class ResourceListPage extends StatelessWidget {
  final ResourceType type;
  final String title;

  const ResourceListPage({
    super.key,
    required this.type,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final resources = MockDataService.getResources()
        .where((r) => r.type == type)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title.toUpperCase(),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView.separated(
        padding: EdgeInsets.all(24.w),
        itemCount: resources.length,
        separatorBuilder: (_, __) => SizedBox(height: 16.h),
        itemBuilder: (context, index) {
          final resource = resources[index];
          return _ResourceListItem(resource: resource);
        },
      ),
    );
  }
}

class _ResourceListItem extends StatelessWidget {
  final Resource resource;

  const _ResourceListItem({required this.resource});

  void _handleOpen(BuildContext context) {
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
        // For mock, we'll assume a dummy path if downloaded
        page = PdfView(path: resource.url, title: resource.title);
        break;
    }

    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page!));
    }

  void _handleDownload(BuildContext context) async {
    final service = DownloadService();
    // Simulate progress for demonstration
    await service.downloadFile(
      resource.url,
      '${resource.id}.file',
      onProgress: (received, total) {
        // In a real app, we'd use a StateProvider/Riverpod to update UI
      },
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Download Complete: ${resource.title}',
          style: const TextStyle(fontFamily: 'Atkinson Hyperlegible'),
        ),
        backgroundColor: LuminaColors.successGreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LuminaCard(
      onTap: () => _handleOpen(context),
      padding: EdgeInsets.all(16.w),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  resource.title,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
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
              size: 28.sp,
            ),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48), // 48px target
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
          width: 8.w,
          height: 8.w,
          decoration: BoxDecoration(
            color: isDownloaded ? LuminaColors.successGreen : LuminaColors.saffron,
            shape: BoxShape.circle,
          ),
        ),
        SizedBox(width: 8.w),
        Text(
          isDownloaded ? 'OFFLINE READY' : 'STREAM FROM SERVER',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: isDownloaded ? LuminaColors.successGreen : LuminaColors.onSurface.withOpacity(0.5),
                fontSize: 10.sp,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}
