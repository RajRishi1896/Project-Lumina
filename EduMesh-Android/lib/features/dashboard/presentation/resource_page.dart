import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/constants/lumina_colors.dart';

import 'package:edumesh_android/features/dashboard/presentation/resource_detail_page.dart';

class ResourcePage extends StatefulWidget {
  final String subject;
  final String grade;

  const ResourcePage({super.key, required this.subject, required this.grade});

  @override
  State<ResourcePage> createState() => _ResourcePageState();
}

class _ResourcePageState extends State<ResourcePage> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    final resources = [
  {"id": "textbooks", "title": "Textbooks", "name": "Textbooks", "subtitle": "Chapter-wise PDFs and study materials", "icon": Icons.menu_book_rounded, "color": cs.primary.withValues(alpha: 0.1), "iconColor": cs.primary},
  {"id": "videos", "title": "Videos", "name": "Videos", "subtitle": "Watch lessons and concept explanations", "icon": Icons.play_circle_fill_rounded, "color": cs.secondary.withValues(alpha: 0.1), "iconColor": cs.secondary},
  {"id": "pyqs", "title": "PYQs", "name": "PYQs", "subtitle": "Previous year papers and practice sets", "icon": Icons.description_rounded, "color": cs.error.withValues(alpha: 0.1), "iconColor": cs.error},
  {"id": "notes", "title": "Notes", "name": "Notes", "subtitle": "Quick revision notes and summaries", "icon": Icons.sticky_note_2_rounded, "color": cs.tertiary.withValues(alpha: 0.1), "iconColor": cs.tertiary},
];

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: cs.surface,
        iconTheme: IconThemeData(color: cs.primary),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.subject, style: TextStyle(color: cs.primary, fontSize: 22.sp, fontWeight: FontWeight.w900)),
            Text(widget.grade, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13.sp, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(18.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(22.w),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26.r),
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F766E), LuminaColors.academicTeal, Color(0xFF14B8A6)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("SMART LEARNING", style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontWeight: FontWeight.w700, fontSize: 10.sp, letterSpacing: 1)),
                  SizedBox(height: 18.h),
                  Text("${widget.subject} \u2022 ${widget.grade}", style: TextStyle(color: Colors.white, fontSize: 24.sp, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            SizedBox(height: 30.h),
            
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: resources.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, crossAxisSpacing: 16.w, mainAxisSpacing: 16.h, childAspectRatio: 0.5,
              ),
              itemBuilder: (context, index) {
                final item = resources[index];
                return Container(
                  padding: EdgeInsets.all(20.w),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(24.r),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: EdgeInsets.all(18.w),
                        decoration: BoxDecoration(color: item['color'] as Color, borderRadius: BorderRadius.circular(22.r)),
                        child: Icon(item['icon'] as IconData, color: item['iconColor'] as Color, size: 34.sp),
                      ),
                      SizedBox(height: 18.h),
                      Text(item['title'] as String, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w800, color: cs.onSurface)),
                      SizedBox(height: 12.h),
                      Expanded(child: Text(item['subtitle'] as String, style: TextStyle(fontSize: 12.sp, color: cs.onSurfaceVariant))),
                      
                      GestureDetector(
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => ResourceDetailPage(
                            title: item['title'] as String,
                            subject: widget.subject,
                            grade: widget.grade,
                            resourceId: item['id'] as String,
                            isInitiallySaved: false,
                          )));
                        },
                        child: Container(
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                          decoration: BoxDecoration(color: (item['iconColor'] as Color).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14.r)),
                          child: Center(child: Text('Open', style: TextStyle(color: item['iconColor'] as Color, fontWeight: FontWeight.w800))),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
