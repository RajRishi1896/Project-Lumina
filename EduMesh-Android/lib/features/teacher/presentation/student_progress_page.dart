import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/constants/lumina_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../data/teacher_repository.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';

class StudentProgressPage extends StatefulWidget {
  final String scholarId;
  final String scholarName;

  const StudentProgressPage({super.key, required this.scholarId, required this.scholarName});

  @override
  State<StudentProgressPage> createState() => _StudentProgressPageState();
}

class _StudentProgressPageState extends State<StudentProgressPage> {
  Map<String, dynamic>? _analytics;
  List<Map<String, dynamic>> _activity = [];
  int _activityTotal = 0;
  int _activityOffset = 0;
  bool _loadingAnalytics = true;
  bool _loadingActivity = true;
  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadAnalytics(), _loadActivity()]);
  }

  Future<void> _loadAnalytics() async {
    setState(() { _loadingAnalytics = true; });
    try {
      final data = await TeacherRepository.getStudentAnalytics(widget.scholarId);
      if (!mounted) return;
      setState(() { _analytics = data; _loadingAnalytics = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loadingAnalytics = false; });
    }
  }

  Future<void> _loadActivity({bool append = false}) async {
    if (!append) setState(() { _loadingActivity = true; _activityOffset = 0; });
    try {
      final data = await TeacherRepository.getStudentActivity(widget.scholarId, offset: _activityOffset);
      if (!mounted) return;
      final items = List<Map<String, dynamic>>.from(data['activity'] ?? []);
      setState(() {
        if (append) { _activity.addAll(items); } else { _activity = items; }
        _activityTotal = data['total'] as int? ?? 0;
        _activityOffset += items.length;
        _loadingActivity = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loadingActivity = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.scholarName)),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView(
          padding: EdgeInsets.all(AppSpacing.lg.w),
          children: [
            _buildOverviewCard(cs),
            SizedBox(height: AppSpacing.lg.h),
            _buildSubjectBreakdown(cs),
            SizedBox(height: AppSpacing.lg.h),
            _buildActivitySection(cs),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewCard(ColorScheme cs) {
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    if (_loadingAnalytics) {
      return const Card(child: Center(child: Padding(padding: EdgeInsets.all(AppSpacing.section), child: CircularProgressIndicator())));
    }
    final a = _analytics;
    if (a == null) {
      return Card(child: Center(child: Padding(padding: const EdgeInsets.all(AppSpacing.xxl), child: Text(l10n.teacherCouldNotLoadAnalytics, style: tt.bodySmall?.copyWith(color: cs.error)))));
    }

    final today = a['study_minutes_today'] as int? ?? 0;
    final week = a['study_minutes_this_week'] as int? ?? 0;
    final month = a['study_minutes_this_month'] as int? ?? 0;
    final streak = a['streak_days'] as int? ?? 0;
    final saved = a['resources_saved'] as int? ?? 0;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.lg.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.teacherOverview, style: tt.titleMedium),
            SizedBox(height: AppSpacing.lg.h),
            Row(
              children: [
                _statBox(cs, l10n.statCardToday, '$today${l10n.suffixMinutes}', Icons.today_rounded, LuminaColors.academicTeal),
                SizedBox(width: AppSpacing.sm.w),
                _statBox(cs, l10n.statCardThisWeek, '$week${l10n.suffixMinutes}', Icons.date_range_rounded, LuminaColors.chartPurple),
                SizedBox(width: AppSpacing.sm.w),
                _statBox(cs, l10n.teacherThisMonth, '$month${l10n.suffixMinutes}', Icons.calendar_month_rounded, LuminaColors.chartBlue),
              ],
            ),
            SizedBox(height: AppSpacing.md.h),
            Row(
              children: [
                _statBox(cs, l10n.statCardStreak, '$streak${l10n.suffixDays}', Icons.local_fire_department_rounded, LuminaColors.chartAmber),
                SizedBox(width: AppSpacing.sm.w),
                _statBox(cs, l10n.statCardSaved, '$saved', Icons.bookmark_rounded, LuminaColors.chartEmerald),
                SizedBox(width: AppSpacing.sm.w),
                Expanded(child: Container()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBox(ColorScheme cs, String label, String value, IconData icon, Color color) {
    final tt = Theme.of(context).textTheme;
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md.h, horizontal: AppSpacing.sm.w),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22.sp),
            SizedBox(height: AppSpacing.sm.h),
            Text(value, style: tt.titleMedium?.copyWith(fontWeight: AppSpacing.weightDisplay, color: color)),
            Text(label, style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectBreakdown(ColorScheme cs) {
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    if (_loadingAnalytics) return const SizedBox.shrink();
    final subjects = _analytics?['subjects'] as List<dynamic>? ?? [];
    if (subjects.isEmpty) return const SizedBox.shrink();

    final totalMinutes = subjects.fold<int>(0, (sum, s) => sum + ((s['minutes'] as int?) ?? 0));

    return Card(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.lg.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.sectionSubjectBreakdown, style: tt.titleMedium),
            SizedBox(height: AppSpacing.md.h),
            ...subjects.take(5).map((s) {
              final name = s['name'] as String? ?? l10n.subjectNameUnknown;
              final minutes = s['minutes'] as int? ?? 0;
              final pct = totalMinutes > 0 ? (minutes / totalMinutes * 100).toStringAsFixed(0) : '0';
              return Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.sm.h),
                child: Row(
                  children: [
                    SizedBox(width: AppSpacing.pageMargin.w, child: Text(name, style: tt.bodySmall, overflow: TextOverflow.ellipsis)),
                SizedBox(width: AppSpacing.sm.w),
                Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4.r),
                        child: LinearProgressIndicator(
                          value: totalMinutes > 0 ? minutes / totalMinutes : 0,
                          minHeight: 8.h,
                          backgroundColor: cs.surfaceContainerHighest,
                        ),
                      ),
                    ),
                    SizedBox(width: AppSpacing.sm.w),
                    SizedBox(width: AppSpacing.touchTarget.w, child: Text('$pct${l10n.suffixPercent}', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant), textAlign: TextAlign.right)),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildActivitySection(ColorScheme cs) {
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.lg.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.sectionRecentActivity, style: tt.titleMedium),
            SizedBox(height: AppSpacing.md.h),
            if (_loadingActivity && _activity.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(AppSpacing.lg), child: CircularProgressIndicator()))
            else if (_activity.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl.h),
                child: Center(child: Text(l10n.teacherNoActivityRecorded, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant))),
              )
            else
              ..._activity.take(50).map((a) => _buildActivityRow(cs, a, l10n)),
            if (_activityOffset < _activityTotal)
              Padding(
                padding: EdgeInsets.only(top: AppSpacing.sm.h),
                child: Center(
                  child: TextButton.icon(
                    onPressed: () => _loadActivity(append: true),
                    icon: const Icon(Icons.expand_more_rounded),
                    label: Text(l10n.teacherShowMore(_activityTotal - _activityOffset)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityRow(ColorScheme cs, Map<String, dynamic> a, AppLocalizations l10n) {
    final tt = Theme.of(context).textTheme;
    final action = a['action'] as String? ?? '';
    final metadata = a['metadata'] as String? ?? '';
    final timestamp = a['timestamp'] as String? ?? '';

    String title = action.replaceAll('_', ' ');
    if (title.isNotEmpty) title = title[0].toUpperCase() + title.substring(1);

    String subtitle = '';
    if (metadata.isNotEmpty) {
      try {
        final decoded = Uri.tryParse(metadata)?.queryParameters;
        subtitle = decoded?['title'] ?? metadata;
      } catch (_) {
        subtitle = metadata.length > 40 ? '${metadata.substring(0, 40)}...' : metadata;
      }
    }

    String timeAgo = '';
    if (timestamp.isNotEmpty) {
      try {
        final dt = DateTime.parse(timestamp);
        final diff = DateTime.now().difference(dt);
        if (diff.inMinutes < 1) {
          timeAgo = l10n.relativeTimeJustNow;
        } else if (diff.inMinutes < 60) {
          timeAgo = l10n.relativeTimeMinutesAgo(diff.inMinutes);
        } else if (diff.inHours < 24) {
          timeAgo = l10n.relativeTimeHoursAgo(diff.inHours);
        } else {
          timeAgo = l10n.relativeTimeDaysAgo(diff.inDays);
        }
      } catch (_) { } }

    IconData icon;
    switch (action) {
      case 'view': case 'resource_view': icon = Icons.visibility_rounded; break;
      case 'download': icon = Icons.download_rounded; break;
      case 'search': icon = Icons.search_rounded; break;
      case 'save': icon = Icons.bookmark_rounded; break;
      default: icon = Icons.circle_rounded;
    }

    return Padding(
      padding: EdgeInsets.only(bottom: AppSpacing.md.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18.sp, color: cs.onSurfaceVariant),
          SizedBox(width: AppSpacing.md.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: tt.bodySmall),
                if (subtitle.isNotEmpty) Text(subtitle, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (timeAgo.isNotEmpty) Text(timeAgo, style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}
