import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'resource_detail_page.dart';

class ResourceCategoryPage extends StatefulWidget {
  final String subject;
  final String grade;

  const ResourceCategoryPage({
    super.key,
    required this.subject,
    required this.grade,
  });

  @override
  State<ResourceCategoryPage> createState() => _ResourceCategoryPageState();
}

class _ResourceCategoryPageState extends State<ResourceCategoryPage> {
  // Your resource categories structure
  final List<Map<String, dynamic>> resources = [
    {
      'id': 'cat_0',
      "title": "Textbooks",
      "subtitle": "Chapter-wise PDFs and study material",
      "icon": Icons.menu_book_rounded,
      "color": const Color(0xFFFFF3E0),
      "iconColor": Colors.orange,
    },
    {
      'id': 'cat_1',
      "title": "Videos",
      "subtitle": "Watch lessons and concept explanations",
      "icon": Icons.play_circle_fill_rounded,
      "color": const Color(0xFFE3F2FD),
      "iconColor": Colors.blue,
    },
    {
      'id': 'cat_2',
      "title": "Question Papers",
      "subtitle": "Previous year papers and practice sets",
      "icon": Icons.description_rounded,
      "color": const Color(0xFFFFEBEE),
      "iconColor": Colors.red,
    },
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F9FC),
        elevation: 0,
        title: Text(
          "${widget.subject} - ${widget.grade}",
          style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800),
        ),
        iconTheme: IconThemeData(color: cs.primary),
      ),
      body: ListView.builder(
        padding: EdgeInsets.all(16.w),
        itemCount: resources.length,
        itemBuilder: (context, index) {
          final item = resources[index];
          return Container(
            margin: EdgeInsets.only(bottom: 16.h),
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(12.w),
                      decoration: BoxDecoration(
                        color: (item['color'] as Color).withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(14.r),
                      ),
                      child: Icon(item['icon'], color: item['iconColor'], size: 28.sp),
                    ),
                    SizedBox(width: 16.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['title']?.toString() ?? '', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16.sp)),
                          Text(item['subtitle'], style: TextStyle(fontSize: 12.sp, color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12.h),
                InkWell(
                  onTap: () {
                    // Navigate to details or filtered list
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ResourceDetailPage(
                          title: item['title'],
                          subject: widget.subject,
                          grade: widget.grade,
                          resourceId: item['id']?.toString() ?? '',
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 10.h),
                    decoration: BoxDecoration(
                      color: (item['iconColor'] as Color).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Open', style: TextStyle(color: item['iconColor'], fontWeight: FontWeight.w800, fontSize: 13.sp)),
                        SizedBox(width: 6.w),
                        Icon(Icons.arrow_forward_rounded, color: item['iconColor'], size: 18.sp),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}