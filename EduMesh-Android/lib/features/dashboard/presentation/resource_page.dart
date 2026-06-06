import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/constants/lumina_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/services/activity_tracker.dart';

import 'package:edumesh_android/features/dashboard/presentation/resource_detail_page.dart';

/// A page that shows resource categories (Textbooks, Videos, PYQs, Notes) for
/// a specific subject and grade.
///
/// Tapping a category navigates to [ResourceDetailPage] filtered by that
/// subject, grade, and resource type.
class ResourcePage extends StatefulWidget {
  /// The subject name used to filter resources.
  final String subject;

  /// The grade level used to filter resources.
  final String grade;

  const ResourcePage({super.key, required this.subject, required this.grade});

  /// Creates the state for the [ResourcePage].
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
            Text(widget.subject, style: TextStyle(color: cs.primary, fontSize: 22.sp, fontWeight: AppSpacing.weightDisplay)),
            Text(widget.grade, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13.sp, fontWeight: AppSpacing.weightStrong)),
          ],
        ),
      ),
      body: SingleChildScrollView(
          padding: EdgeInsets.all(AppSpacing.lg.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(AppSpacing.xxl.w),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppSpacing.radiusXl.r),
                color: LuminaColors.academicTeal,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.subject.toUpperCase(), style: TextStyle(color: cs.onPrimary, fontWeight: AppSpacing.weightStrong, fontSize: 10.sp, letterSpacing: 1)),
                  SizedBox(height: AppSpacing.lg.h),
                  Text("${widget.subject} \u2022 ${widget.grade}", style: TextStyle(color: cs.onPrimary, fontSize: 24.sp, fontWeight: AppSpacing.weightDisplay)),
                ],
              ),
            ),
            SizedBox(height: AppSpacing.section.h),
            
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: resources.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, crossAxisSpacing: 16.w, mainAxisSpacing: 16.h, childAspectRatio: 0.75,
              ),
              itemBuilder: (context, index) {
                final item = resources[index];
                return Container(
                  padding: EdgeInsets.all(AppSpacing.xl.w),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusXl.r),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(item['icon'] as IconData, color: item['iconColor'] as Color, size: 30.sp),
                      SizedBox(height: AppSpacing.md.h),
                      Text(item['title'] as String, style: TextStyle(fontSize: 14.sp, fontWeight: AppSpacing.weightDisplay, color: cs.onSurface)),
                      SizedBox(height: AppSpacing.sm.h),
                      Expanded(child: Text(item['subtitle'] as String, style: TextStyle(fontSize: 12.sp, color: cs.onSurfaceVariant))),
                      
                      GestureDetector(
                        onTap: () {
                          ActivityTracker().logAction('view', resourceId: item['id'] as String, metadata: widget.subject).catchError((_) {});
                          Navigator.push(context, MaterialPageRoute(builder: (_) => ResourceDetailPage(
                            title: item['title'] as String,
                            subject: widget.subject,
                            grade: widget.grade,
                            resourceType: item['id'] as String,
                            isInitiallySaved: false,
                          )));
                        },
                        child: Container(
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(vertical: AppSpacing.md.h),
                          decoration: BoxDecoration(color: (item['iconColor'] as Color).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppSpacing.radiusMd.r)),
                          child: Center(child: Text('Open', style: TextStyle(color: item['iconColor'] as Color, fontWeight: AppSpacing.weightDisplay))),
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
