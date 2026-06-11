import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/services/activity_tracker.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';

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
    final l10n = AppLocalizations.of(context)!;

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
            Text(widget.subject, style: TextStyle(color: cs.onSurface, fontSize: 28.sp, fontWeight: AppSpacing.weightDisplay)),
            SizedBox(height: AppSpacing.xs.h),
            Text(widget.grade, style: TextStyle(fontSize: 15.sp, color: cs.onSurfaceVariant)),
            SizedBox(height: AppSpacing.section.h),
            Text(l10n.resourcePageResources, style: TextStyle(fontSize: 13.sp, fontWeight: AppSpacing.weightStrong, color: cs.onSurfaceVariant)),
            SizedBox(height: AppSpacing.md.h),
            _resourceRow(context, l10n.resourceTypeTextbooks, l10n.resourceTypeTextbooksSubtitle, 'textbooks'),
            Divider(height: 1, color: cs.outlineVariant),
            _resourceRow(context, l10n.resourceTypeVideos, l10n.resourceTypeVideosSubtitle, 'videos'),
            Divider(height: 1, color: cs.outlineVariant),
            _resourceRow(context, l10n.resourceTypePyqs, l10n.resourceTypePyqsSubtitle, 'pyqs'),
            Divider(height: 1, color: cs.outlineVariant),
            _resourceRow(context, l10n.resourceTypeNotes, l10n.resourceTypeNotesSubtitle, 'notes'),
          ],
        ),
      ),
    );
  }

  Widget _resourceRow(BuildContext context, String title, String subtitle, String id) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () {
        ActivityTracker().logAction('view', resourceId: id, metadata: widget.subject).catchError((_) {});
        Navigator.push(context, MaterialPageRoute(builder: (_) => ResourceDetailPage(
          title: title, subject: widget.subject, grade: widget.grade,
          resourceType: id, isInitiallySaved: false,
        )));
      },
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg.h),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 16.sp, fontWeight: AppSpacing.weightStrong, color: cs.onSurface)),
                  SizedBox(height: AppSpacing.xs.h),
                  Text(subtitle, style: TextStyle(fontSize: 13.sp, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant, size: 20.sp),
          ],
        ),
      ),
    );
  }
}
