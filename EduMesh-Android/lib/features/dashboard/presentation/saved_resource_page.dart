import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:edumesh_android/core/models/resource_model.dart';
import 'package:edumesh_android/shared/services/mock_data_service.dart';
import 'package:edumesh_android/shared/services/save_resource_service.dart';

class SavedResourcesPage extends StatelessWidget {
  const SavedResourcesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.surface,
          elevation: 0,
          title: Text(
            "Saved Resources",
            style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.bold),
          ),
          bottom: TabBar(
            labelColor: cs.primary,
            unselectedLabelColor: cs.onSurfaceVariant,
            indicatorColor: cs.primary,
            indicatorWeight: 3.0,
            tabs: const [
              Tab(text: "Textbooks"),
              Tab(text: "Videos"),
              Tab(text: "PYQs"),
              Tab(text: "Notes"),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
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
  final ResourceType type; 
  const _SavedListByType({required this.type});

  @override
  State<_SavedListByType> createState() => _SavedListByTypeState();
}

class _SavedListByTypeState extends State<_SavedListByType> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final allResources = MockDataService.getResources();
    
    final savedItems = allResources.where((r) => 
      r.isDownloaded && r.type == widget.type
    ).toList();

    if (savedItems.isEmpty) {
      return Center(
        child: Text(
          "No saved ${widget.type.name}s found.",
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      itemCount: savedItems.length,
      itemBuilder: (context, index) {
        final item = savedItems[index];
        return Container(
          margin: EdgeInsets.only(bottom: 10.h),
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
              IconButton(
                icon: Icon(Icons.bookmark_remove, color: cs.error),
                onPressed: () async {
                  await SaveResourceService.toggleSaveStatus(item.id);
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),
        );
      },
    );
  }
}