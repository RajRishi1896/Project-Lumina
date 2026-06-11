import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/constants/lumina_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/network/api_client.dart';
import '../data/teacher_repository.dart';
import 'student_progress_page.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';

class TeacherMonitorPage extends StatefulWidget {
  const TeacherMonitorPage({super.key});

  @override
  State<TeacherMonitorPage> createState() => _TeacherMonitorPageState();
}

class _TeacherMonitorPageState extends State<TeacherMonitorPage> {
  List<Map<String, dynamic>> _allStudents = [];
  List<Map<String, dynamic>> _filteredStudents = [];
  List<String> _grades = [];
  String? _selectedGrade;
  String _searchQuery = '';
  bool _loading = true;
  String? _error;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() { _loading = true; _error = null; });
    try {
      final gradesResp = await ApiClient.get('/grades');
      final gradesList = List<Map<String, dynamic>>.from(gradesResp.data ?? []);
      final grades = <String>[];
      for (final g in gradesList) {
        final name = g['name'] as String?;
        if (name != null && name.isNotEmpty) grades.add(name);
      }

      final students = await TeacherRepository.getStudents(grade: _selectedGrade);

      if (!mounted) return;
      setState(() {
        _grades = grades;
        _allStudents = students;
        _applySearch();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _applySearch() {
    final query = _searchQuery.toLowerCase().trim();
    if (query.isEmpty) {
      _filteredStudents = List.from(_allStudents);
    } else {
      _filteredStudents = _allStudents.where((s) {
        final name = (s['name'] as String? ?? '').toLowerCase();
        final username = (s['username'] as String? ?? '').toLowerCase();
        final grade = (s['grade'] as String? ?? '').toLowerCase();
        return name.contains(query) || username.contains(query) || grade.contains(query);
      }).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.teacherPageTitle),
        actions: [
          if (_grades.isNotEmpty)
            PopupMenuButton<String?>(
              icon: const Icon(Icons.filter_list_rounded),
              tooltip: l10n.teacherFilterByGrade,
              onSelected: (grade) {
                setState(() { _selectedGrade = grade; });
                _loadData();
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: null, child: Text(l10n.teacherAllGrades, style: TextStyle(fontWeight: _selectedGrade == null ? AppSpacing.weightStrong : AppSpacing.weightBody))),
                ..._grades.map((g) => PopupMenuItem(value: g, child: Text(g, style: TextStyle(fontWeight: _selectedGrade == g ? AppSpacing.weightStrong : AppSpacing.weightBody)))),
              ],
            ),
        ],
      ),
      body: _buildBody(cs),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    final l10n = AppLocalizations.of(context)!;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 48.sp, color: cs.error),
              SizedBox(height: 12.h),
              Text(l10n.teacherCouldNotLoadStudents, style: TextStyle(fontSize: 16.sp, fontWeight: AppSpacing.weightStrong)),
              SizedBox(height: 4.h),
              Text(l10n.teacherCheckHubConnection, style: TextStyle(fontSize: 14.sp, color: cs.onSurfaceVariant)),
              SizedBox(height: 16.h),
              FilledButton.tonalIcon(onPressed: _loadData, icon: const Icon(Icons.refresh_rounded), label: Text(l10n.teacherRetry)),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        if (_selectedGrade != null)
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            color: LuminaColors.academicTeal.withValues(alpha: 0.08),
            child: Row(
              children: [
                Icon(Icons.filter_alt_rounded, size: 16.sp, color: LuminaColors.academicTeal),
                SizedBox(width: 8.w),
                Expanded(child: Text(l10n.teacherShowing(_selectedGrade!), style: TextStyle(fontSize: 13.sp, color: LuminaColors.academicTeal))),
                GestureDetector(
                  onTap: () { setState(() { _selectedGrade = null; }); _loadData(); },
                  child: Icon(Icons.close_rounded, size: 18.sp, color: LuminaColors.academicTeal),
                ),
              ],
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: l10n.teacherSearchStudentsHint,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear_rounded), onPressed: () { _searchController.clear(); setState(() { _searchQuery = ''; _applySearch(); }); })
                  : null,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 12.w),
            ),
            onChanged: (v) { setState(() { _searchQuery = v; _applySearch(); }); },
          ),
        ),
        if (_filteredStudents.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline_rounded, size: 48.sp, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                  SizedBox(height: 12.h),
                  Text(_searchQuery.isNotEmpty ? l10n.teacherNoStudentsMatchSearch : l10n.teacherNoStudentsFound, style: TextStyle(fontSize: 16.sp, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadData,
              child: ListView.builder(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
                itemCount: _filteredStudents.length,
                itemBuilder: (_, i) => _buildStudentCard(cs, _filteredStudents[i]),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStudentCard(ColorScheme cs, Map<String, dynamic> s) {
    final l10n = AppLocalizations.of(context)!;
    final name = s['name'] as String? ?? 'Unknown';
    final grade = s['grade'] as String? ?? '';
    final todayMin = s['study_minutes_today'] as int? ?? 0;
    final streak = s['streak_days'] as int? ?? 0;
    final saved = s['resources_saved'] as int? ?? 0;
    final downloaded = s['resources_downloaded'] as int? ?? 0;
    final lastActive = s['last_active'] as String? ?? '';

    String timeAgo = '';
    if (lastActive.isNotEmpty) {
      try {
        final dt = DateTime.parse(lastActive);
        final diff = DateTime.now().difference(dt);
        if (diff.inMinutes < 1) timeAgo = l10n.relativeTimeJustNow;
        else if (diff.inMinutes < 60) timeAgo = l10n.relativeTimeMinutesAgo(diff.inMinutes);
        else if (diff.inHours < 24) timeAgo = l10n.relativeTimeHoursAgo(diff.inHours);
        else timeAgo = l10n.relativeTimeDaysAgo(diff.inDays);
      } catch (_) { timeAgo = ''; }
    }

    return Card(
      margin: EdgeInsets.only(bottom: 8.h),
      child: InkWell(
        borderRadius: BorderRadius.circular(12.r),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StudentProgressPage(scholarId: s['id'] as String, scholarName: name))),
        child: Padding(
          padding: EdgeInsets.all(14.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20.r,
                    backgroundColor: LuminaColors.academicTeal.withValues(alpha: 0.15),
                    child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: TextStyle(fontSize: 16.sp, fontWeight: AppSpacing.weightStrong, color: LuminaColors.academicTeal)),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: TextStyle(fontSize: 15.sp, fontWeight: AppSpacing.weightStrong)),
                        Row(
                          children: [
                            if (grade.isNotEmpty) Text(grade, style: TextStyle(fontSize: 12.sp, color: cs.onSurfaceVariant)),
                            if (grade.isNotEmpty && timeAgo.isNotEmpty) Text(' · ', style: TextStyle(fontSize: 12.sp, color: cs.onSurfaceVariant)),
                            if (timeAgo.isNotEmpty) Text(timeAgo, style: TextStyle(fontSize: 12.sp, color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                ],
              ),
              SizedBox(height: 10.h),
              Row(
                children: [
                  _statChip(cs, Icons.timer_rounded, '${todayMin}m', l10n.teacherLabelToday),
                  SizedBox(width: 8.w),
                  _statChip(cs, Icons.local_fire_department_rounded, '$streak d', l10n.teacherLabelStreak),
                  SizedBox(width: 8.w),
                  _statChip(cs, Icons.bookmark_rounded, '$saved', l10n.teacherLabelSaved),
                  SizedBox(width: 8.w),
                  _statChip(cs, Icons.download_rounded, '$downloaded', l10n.teacherLabelDownloaded),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statChip(ColorScheme cs, IconData icon, String value, String label) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12.sp, color: cs.onSurfaceVariant),
          SizedBox(width: 4.w),
          Text(value, style: TextStyle(fontSize: 11.sp, fontWeight: AppSpacing.weightStrong)),
          if (label.isNotEmpty) ...[
            SizedBox(width: 2.w),
            Text(label, style: TextStyle(fontSize: 10.sp, color: cs.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}
