import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:edumesh_android/core/models/course.dart';
import 'package:edumesh_android/core/services/course_service.dart';
import 'package:edumesh_android/core/recommendation/on_device_scorer.dart';
import 'package:edumesh_android/core/constants/app_spacing.dart';
import 'package:edumesh_android/features/auth/data/auth_service.dart';
import 'package:edumesh_android/shared/services/connectivity_service.dart';
import 'package:edumesh_android/core/storage/db_helper.dart';
import 'course_player_page.dart';

class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key});

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  bool _loading = true;
  List<Course> _recommended = [];
  List<Course> _allCourses = [];
  List<({Course course, Map<String, dynamic>? progress})> _enrolledCourses = [];
  List<Course> _similarCourses = [];
  String? _grade;
  String? _error;
  String _searchQuery = '';
  bool _showAll = false;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadData();
    CourseService().addListener(_onCourseServiceChanged);
  }

  void _onCourseServiceChanged() {
    if (!mounted) return;
    setState(() {
      _enrolledCourses = CourseService().enrolledCourses;
    });
  }

  Future<void> _loadData() async {
    _loading = true;
    if (mounted) setState(() {});

    try {
      _grade = await AuthService().getStudentGrade();

      if (ConnectivityService().isOnline) {
        await CourseService().fetchCatalog();
      }

      _allCourses = await CourseService().getCachedCatalog();

      await CourseService().loadEnrolledCourses();
      _enrolledCourses = CourseService().enrolledCourses;

      if (_grade != null && _grade!.isNotEmpty) {
        _recommended = await OnDeviceScorer.getRecommendedCourses('', _grade!);
      }

      final db = await DBHelper().database;
      final similarRows = await db.query('similar_courses');
      final similarIds = similarRows.map((r) => (r['similar_course_id'] ?? '').toString()).toSet();
      _similarCourses = _allCourses.where((c) => similarIds.contains(c.id)).toList();
    } catch (e) {
      _error = e.toString();
    }

    _loading = false;
    if (mounted) setState(() {});
  }

  List<Course> get _filteredCourses {
    if (_searchQuery.isEmpty) return _allCourses;
    final q = _searchQuery.toLowerCase();
    return _allCourses.where((c) =>
      c.title.toLowerCase().contains(q) ||
      c.subject.toLowerCase().contains(q) ||
      c.description?.toLowerCase().contains(q) == true
    ).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    CourseService().removeListener(_onCourseServiceChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (_loading) {
      return Scaffold(
        backgroundColor: cs.surface,
        body: SafeArea(child: Center(child: CircularProgressIndicator(strokeWidth: 3.w))),
      );
    }

    if (_error != null && _allCourses.isEmpty && _enrolledCourses.isEmpty) {
      return Scaffold(
        backgroundColor: cs.surface,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.lg.w),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48.sp, color: cs.error),
                  SizedBox(height: AppSpacing.md.h),
                  Text('Could not load courses', style: tt.bodyLarge?.copyWith(color: cs.onSurface)),
                  SizedBox(height: AppSpacing.sm.h),
                  Text(_error!, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  SizedBox(height: AppSpacing.lg.h),
                  FilledButton(onPressed: _loadData, child: const Text('Retry')),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSearchBar(cs, tt),
              SizedBox(height: AppSpacing.md.h),

              if (_enrolledCourses.isNotEmpty) ...[
                _buildSectionHeader(cs, tt, 'My Courses'),
                SizedBox(height: AppSpacing.sm.h),
                _buildEnrolledList(cs, tt),
                SizedBox(height: AppSpacing.section.h),
              ],

              if (_recommended.isNotEmpty && !_showAll) ...[
                _buildSectionHeader(cs, tt, 'Recommended for You'),
                SizedBox(height: AppSpacing.sm.h),
                _buildHorizontalList(_recommended, cs, tt),
                SizedBox(height: AppSpacing.section.h),
              ],

              if (_similarCourses.isNotEmpty && !_showAll) ...[
                _buildSectionHeader(cs, tt, 'Similar Courses'),
                SizedBox(height: AppSpacing.sm.h),
                _buildHorizontalList(_similarCourses, cs, tt),
                SizedBox(height: AppSpacing.section.h),
              ],

              _buildSectionHeader(cs, tt, 'All Courses',
                trailing: _recommended.isNotEmpty
                  ? TextButton(
                      onPressed: () => setState(() => _showAll = !_showAll),
                      child: Text(_showAll ? 'Show Recommended' : 'Show All'),
                    )
                  : null,
              ),
              SizedBox(height: AppSpacing.sm.h),
              _buildAllCoursesList(cs, tt),
              SizedBox(height: AppSpacing.xxl.h),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(ColorScheme cs, TextTheme tt, String title, {Widget? trailing}) {
    return Row(
      children: [
        Text(title, style: tt.titleLarge?.copyWith(fontWeight: AppSpacing.weightDisplay, color: cs.onSurface)),
        const Spacer(),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildSearchBar(ColorScheme cs, TextTheme tt) {
    return Padding(
      padding: EdgeInsets.only(top: AppSpacing.lg.h),
      child: TextField(
        controller: _searchController,
        onChanged: (v) {
          _searchDebounce?.cancel();
          _searchDebounce = Timer(const Duration(milliseconds: 300), () {
            if (mounted) setState(() => _searchQuery = v);
          });
        },
        decoration: InputDecoration(
          hintText: 'Search courses...',
          prefixIcon: Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
          suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: Icon(Icons.clear, color: cs.onSurfaceVariant),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              )
            : null,
          filled: true,
          fillColor: cs.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm.r),
            borderSide: BorderSide.none,
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w, vertical: AppSpacing.md.h),
        ),
      ),
    );
  }

  Widget _buildEnrolledList(ColorScheme cs, TextTheme tt) {
    return SizedBox(
      height: 200.h,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _enrolledCourses.length,
        separatorBuilder: (_, __) => SizedBox(width: AppSpacing.md.w),
        itemBuilder: (ctx, i) {
          final entry = _enrolledCourses[i];
          final course = entry.course;
          final progress = entry.progress;
          final completedCount = (progress?['completed_count'] as num?)?.toInt() ?? 0;
          final totalResources = (progress?['total_resources'] as num?)?.toInt() ?? 0;
          final pct = totalResources > 0 ? completedCount / totalResources : 0.0;

          return SizedBox(
            width: 200.w,
            child: Card(
              child: InkWell(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => CoursePlayerPage(course: course),
                  ));
                },
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm.r),
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.lg.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 72.h,
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(AppSpacing.radiusSm.r),
                        ),
                        child: Center(
                          child: Icon(Icons.school, size: 28.sp, color: cs.primary),
                        ),
                      ),
                      SizedBox(height: AppSpacing.sm.h),
                      Text(course.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: tt.titleSmall?.copyWith(color: cs.onSurface)),
                      SizedBox(height: AppSpacing.xs.h),
                      LinearProgressIndicator(value: pct, backgroundColor: cs.surfaceContainerHighest),
                      SizedBox(height: AppSpacing.xs.h),
                      Text('$completedCount / $totalResources',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () {
                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => CoursePlayerPage(course: course),
                            ));
                          },
                          child: const Text('Continue'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHorizontalList(List<Course> courses, ColorScheme cs, TextTheme tt) {
    return SizedBox(
      height: 280.h,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: courses.length,
        separatorBuilder: (_, __) => SizedBox(width: AppSpacing.md.w),
        itemBuilder: (ctx, i) => SizedBox(
          width: 200.w,
          child: _buildCourseCard(courses[i], cs, tt),
        ),
      ),
    );
  }

  Widget _buildCourseCard(Course course, ColorScheme cs, TextTheme tt) {
    final isEnrolled = _enrolledCourses.any((e) => e.course.id == course.id);
    return Card(
      child: InkWell(
        onTap: isEnrolled
          ? () {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => CoursePlayerPage(course: course),
              ));
            }
          : null,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm.r),
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 80.h,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm.r),
                ),
                child: Center(
                  child: Icon(Icons.school, size: 32.sp, color: cs.primary),
                ),
              ),
              SizedBox(height: AppSpacing.sm.h),
              Text(course.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: tt.titleSmall?.copyWith(color: cs.onSurface)),
              SizedBox(height: AppSpacing.xs.h),
              Row(
                children: [
                  Chip(
                    label: Text(course.subject, style: tt.labelSmall),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                  SizedBox(width: AppSpacing.xs.w),
                  Chip(
                    label: Text('Class ${course.grade}', style: tt.labelSmall),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
              const Spacer(),
              if (isEnrolled)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => CoursePlayerPage(course: course),
                      ));
                    },
                    child: const Text('Continue'),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      await CourseService().enroll(course.id);
                      if (mounted) await _loadData();
                    },
                    child: const Text('Enroll'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAllCoursesList(ColorScheme cs, TextTheme tt) {
    final courses = _filteredCourses;
    if (courses.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.section.h),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.search_off, size: 40.sp, color: cs.onSurfaceVariant),
              SizedBox(height: AppSpacing.md.h),
              Text(_searchQuery.isNotEmpty ? 'No matching courses' : 'No courses available',
                style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: courses.length,
      itemBuilder: (ctx, i) => Padding(
        padding: EdgeInsets.only(bottom: AppSpacing.md.h),
        child: _buildCourseCard(courses[i], cs, tt),
      ),
    );
  }
}
