import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:edumesh_android/core/models/resource_model.dart';
import 'package:edumesh_android/shared/services/mock_data_service.dart';
import 'package:edumesh_android/shared/services/save_resource_service.dart';

class ResourceDetailPage extends StatefulWidget {
  final String title;
  final String subject;
  final String grade;
  final String resourceId;
  final bool isInitiallySaved;

  const ResourceDetailPage({
    super.key,
    required this.title,
    required this.subject,
    required this.grade,
    required this.resourceId,
    this.isInitiallySaved = false,
  });

  @override
  State<ResourceDetailPage> createState() => _ResourceDetailPageState();
}

class _ResourceDetailPageState extends State<ResourceDetailPage> {
  List<ResourceModel> items = [];

  @override
  void initState() {
    super.initState();
    _loadResources();
  }

  void _loadResources() {
    final all = MockDataService.getResources();
    setState(() {
      items = all.where((r) => 
        r.subject == widget.subject && 
        r.grade == widget.grade
      ).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(title: Text(widget.title)),
      body: ListView.builder(
        padding: EdgeInsets.all(20.w),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return Card(
            margin: EdgeInsets.only(bottom: 16.h),
            child: ListTile(
              title: Text(item.title),
              subtitle: Text("${item.subject} • ${item.grade}"),
              trailing: IconButton(
                icon: Icon(
                  item.isDownloaded ? Icons.bookmark : Icons.bookmark_border,
                  color: item.isDownloaded ? cs.primary : Colors.grey,
                ),
                onPressed: () async {
                  await SaveResourceService.toggleSaveStatus(item.id);
                  setState(() {}); 
                },
              ),
            ),
          );
        },
      ),
    );
  }
}