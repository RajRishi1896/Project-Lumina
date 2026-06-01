import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:edumesh_android/core/constants/lumina_colors.dart';
import 'package:edumesh_android/features/auth/data/auth_service.dart';
import '../../../core/services/activity_tracker.dart';
import 'dart:convert';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../../core/network/api_client.dart';

class StudentProfilePage extends StatefulWidget {
  const StudentProfilePage({super.key});

  @override
  State<StudentProfilePage> createState() => _StudentProfilePageState();
}

class _StudentProfilePageState extends State<StudentProfilePage> {
  final ActivityTracker _tracker = ActivityTracker();
  String _studentName = 'Alex Rivera';
  final String _studentId = 'LUMINA_01-A1B2C3D4';
  String _grade = 'Grade 11';
  int _studyMinutesToday = 0;
  int _studyMinutesThisWeek = 0;
  int _resourcesSaved = 0;
  int _streakDays = 0;
  bool _showAllActivity = false;
  List<_SubjectTime> _subjectBreakdown = [];
  List<Map<String, dynamic>> _activityHistory = [];
  bool _loading = true;
  File? _profileImage;
  bool _uploadingIcon = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final analytics = await _tracker.getAnalytics();
      final history = await _tracker.getActivityHistory(limit: 25);
      if (mounted) {
        setState(() {
          _studyMinutesToday = ((analytics['study_minutes_today'] ?? 0) as num).toInt();
          _studyMinutesThisWeek = ((analytics['study_minutes_this_week'] ?? 0) as num).toInt();
          _resourcesSaved = ((analytics['resources_saved'] ?? 0) as num).toInt();
          _streakDays = ((analytics['streak_days'] ?? 0) as num).toInt();
          final subjects = analytics['subjects'] as List<dynamic>? ?? [];
          _subjectBreakdown = subjects.map((s) => _SubjectTime(
            s['name']?.toString() ?? '',
            ((s['minutes'] ?? 0) as num).toInt(),
            _colorForSubject(s['name']?.toString() ?? ''),
          )).toList();
          _activityHistory = history;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _colorForSubject(String name) {
    const colors = [
      LuminaColors.academicTeal,
      Color(0xFF7C3AED),
      Color(0xFF059669),
      Color(0xFF0891B2),
      Color(0xFFD97706),
      Color(0xFFDC2626),
    ];
    return colors[name.length % colors.length];
  }

  String _formatActivityTitle(Map<String, dynamic> activity) {
    final action = (activity['action'] as String? ?? '').toLowerCase();
    final resourceId = activity['resource_id'] as String? ?? '';
    String verb;
    switch (action) {
      case 'view':
        verb = 'Viewed';
        break;
      case 'search':
        verb = 'Searched';
        break;
      case 'download':
        verb = 'Downloaded';
        break;
      case 'watch':
        verb = 'Watched';
        break;
      case 'save':
        verb = 'Saved';
        break;
      case 'open':
        verb = 'Opened';
        break;
      case 'complete':
        verb = 'Completed';
        break;
      case '':
        verb = '';
        break;
      default:
        verb = action.isNotEmpty
            ? '${action[0].toUpperCase()}${action.substring(1)}ed'
            : '';
    }
    if (resourceId.isEmpty) return verb;
    return '$verb $resourceId';
  }

  String _formatRelativeTime(dynamic timestamp) {
    if (timestamp == null) return '';
    DateTime dateTime;
    if (timestamp is DateTime) {
      dateTime = timestamp;
    } else if (timestamp is int) {
      dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    } else if (timestamp is String) {
      dateTime = DateTime.parse(timestamp);
    } else {
      return '';
    }
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hour${diff.inHours > 1 ? 's' : ''} ago';
    if (diff.inDays < 30) return '${diff.inDays} day${diff.inDays > 1 ? 's' : ''} ago';
    return '${diff.inDays ~/ 30} month${diff.inDays ~/ 30 > 1 ? 's' : ''} ago';
  }

  IconData _iconForAction(String action) {
    switch (action) {
      case 'view':
        return Icons.menu_book_rounded;
      case 'search':
        return Icons.search_rounded;
      case 'download':
        return Icons.download_rounded;
      case 'watch':
        return Icons.play_circle_rounded;
      default:
        return Icons.circle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: _loading
            ? Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _buildHeader(cs),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.symmetric(horizontal: 16.w),
                      children: [
                        _buildProfileCard(cs),
                        SizedBox(height: 20.h),
                        _buildStatsRow(cs),
                        SizedBox(height: 24.h),
                        _buildSubjectBreakdown(cs),
                        SizedBox(height: 24.h),
                        _buildRecentActivity(cs),
                        SizedBox(height: 24.h),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant, width: 1)),
      ),
      child: Row(
        children: [
          Icon(Icons.person_rounded, color: cs.primary, size: 24.sp),
          SizedBox(width: 12.w),
          Text('My Profile',
              style: GoogleFonts.atkinsonHyperlegible(
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w700,
                  color: cs.primary)),
          const Spacer(),
          Icon(Icons.bar_chart_rounded, color: cs.primary, size: 20.sp),
          SizedBox(width: 4.w),
          Text('Analytics',
              style: GoogleFonts.atkinsonHyperlegible(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Future<void> _pickAndUploadIcon() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 256, maxHeight: 256);
    if (picked == null) return;
    setState(() => _uploadingIcon = true);
    try {
      final bytes = await picked.readAsBytes();
      final b64 = base64Encode(bytes);
      final ext = picked.path.split('.').last;
      final scholarId = await AuthService().getUniqueUserId();
      if (scholarId == null) {
        if (mounted) setState(() => _uploadingIcon = false);
        return;
      }
      await ApiClient.post('/student/profile/icon', data: {
        'scholar_id': scholarId,
        'image_data': b64,
        'image_ext': ext,
      });
      if (mounted) {
        setState(() {
          _profileImage = File(picked.path);
          _uploadingIcon = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _uploadingIcon = false);
    }
  }

  Widget _buildProfileCard(ColorScheme cs) {
    return Container(
      margin: EdgeInsets.only(top: 16.h),
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _pickAndUploadIcon,
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 32.r,
                  backgroundColor: LuminaColors.academicTeal,
                  backgroundImage: _profileImage != null ? FileImage(_profileImage!) : null,
                  child: _profileImage == null
                      ? Text('AR',
                          style: GoogleFonts.atkinsonHyperlegible(
                              fontSize: 22.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.white))
                      : null,
                ),
                if (_uploadingIcon)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: SizedBox(
                          width: 20.sp,
                          height: 20.sp,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: EdgeInsets.all(4.w),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.camera_alt, size: 12.sp, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_studentName,
                    style: GoogleFonts.atkinsonHyperlegible(
                        fontSize: 20.sp,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface)),
                SizedBox(height: 4.h),
                Row(
                  children: [
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                      decoration: BoxDecoration(
                        color: LuminaColors.academicTeal.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4.r),
                      ),
                      child: Text('Student',
                          style: TextStyle(
                              fontSize: 11.sp,
                              color: LuminaColors.academicTeal,
                              fontWeight: FontWeight.w600)),
                    ),
                    SizedBox(width: 8.w),
                    Text(_grade,
                        style: TextStyle(
                            fontSize: 13.sp,
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
                SizedBox(height: 4.h),
                Text(_studentId,
                    style: TextStyle(
                        fontSize: 11.sp, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.edit_rounded, size: 20.sp, color: cs.onSurfaceVariant),
            onPressed: () => _showEditProfileSheet(cs),
          ),
        ],
      ),
    );
  }

  void _showEditProfileSheet(ColorScheme cs) {
    final nameController = TextEditingController(text: _studentName);
    final gradeController = TextEditingController(text: _grade);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Padding(
              padding: EdgeInsets.all(24.w),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.edit_rounded, color: cs.primary, size: 22.sp),
                      SizedBox(width: 10.w),
                      Text('Edit Profile',
                          style: GoogleFonts.atkinsonHyperlegible(
                              fontSize: 20.sp,
                              fontWeight: FontWeight.w700,
                              color: cs.primary)),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.close_rounded, size: 22.sp),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  SizedBox(height: 20.h),
                  Text('Full Name',
                      style: GoogleFonts.atkinsonHyperlegible(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant)),
                  SizedBox(height: 6.h),
                  TextField(
                    controller: nameController,
                    style: GoogleFonts.atkinsonHyperlegible(
                        fontSize: 15.sp, color: cs.onSurface),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: cs.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                    ),
                  ),
                  SizedBox(height: 16.h),
                  Text('Grade',
                      style: GoogleFonts.atkinsonHyperlegible(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant)),
                  SizedBox(height: 6.h),
                  TextField(
                    controller: gradeController,
                    style: GoogleFonts.atkinsonHyperlegible(
                        fontSize: 15.sp, color: cs.onSurface),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: cs.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                    ),
                  ),
                  SizedBox(height: 16.h),
                  Text('Student ID',
                      style: GoogleFonts.atkinsonHyperlegible(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant)),
                  SizedBox(height: 6.h),
                  TextField(
                    controller: TextEditingController(text: _studentId),
                    enabled: false,
                    style: GoogleFonts.atkinsonHyperlegible(
                        fontSize: 15.sp, color: cs.onSurfaceVariant),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: cs.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                    ),
                  ),
                  SizedBox(height: 24.h),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _studentName = nameController.text.trim().isNotEmpty
                              ? nameController.text.trim()
                              : _studentName;
                          _grade = gradeController.text.trim().isNotEmpty
                              ? gradeController.text.trim()
                              : _grade;
                        });
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                      ),
                      child: Text('Save Changes',
                          style: GoogleFonts.atkinsonHyperlegible(
                              fontSize: 15.sp,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).then((_) {
      nameController.dispose();
      gradeController.dispose();
    });
  }

  Widget _buildStatsRow(ColorScheme cs) {
    return Row(
      children: [
        Expanded(child: _buildStatCard(cs, 'Today', '${_studyMinutesToday}m', Icons.today_rounded, LuminaColors.academicTeal)),
        SizedBox(width: 10.w),
        Expanded(child: _buildStatCard(cs, 'This Week', '${(_studyMinutesThisWeek / 60).toStringAsFixed(1)}h', Icons.date_range_rounded, const Color(0xFF7C3AED))),
        SizedBox(width: 10.w),
        Expanded(child: _buildStatCard(cs, 'Saved', '$_resourcesSaved', Icons.bookmark_rounded, const Color(0xFF059669))),
        SizedBox(width: 10.w),
        Expanded(child: _buildStatCard(cs, 'Streak', '$_streakDays d', Icons.local_fire_department_rounded, const Color(0xFFD97706))),
      ],
    );
  }

  Widget _buildStatCard(ColorScheme cs, String label, String value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 14.h, horizontal: 8.w),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22.sp),
          SizedBox(height: 8.h),
          Text(value,
              style: GoogleFonts.atkinsonHyperlegible(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface)),
          SizedBox(height: 2.h),
          Text(label,
              style: TextStyle(fontSize: 10.sp, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildSubjectBreakdown(ColorScheme cs) {
    final total = _subjectBreakdown.fold(0, (sum, s) => sum + s.minutes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Study Time by Subject',
            style: GoogleFonts.atkinsonHyperlegible(
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
                color: cs.onSurface)),
        SizedBox(height: 12.h),
        Container(
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            children: [
              ...List.generate(_subjectBreakdown.length, (i) {
                final sub = _subjectBreakdown[i];
                final pct = total > 0
                    ? sub.minutes / total
                    : 0.0;
                final hours = '${(sub.minutes / 60).toStringAsFixed(1)}h';
                return Padding(
                  padding: EdgeInsets.only(bottom: i < _subjectBreakdown.length - 1 ? 14.h : 0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(sub.name,
                                style: TextStyle(
                                    fontSize: 13.sp,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurface)),
                          ),
                          Text(hours,
                              style: TextStyle(
                                  fontSize: 12.sp,
                                  color: cs.onSurfaceVariant)),
                          SizedBox(width: 8.w),
                          Text('${(pct * 100).toStringAsFixed(0)}%',
                              style: TextStyle(
                                  fontSize: 12.sp,
                                  color: cs.onSurfaceVariant)),
                        ],
                      ),
                      SizedBox(height: 6.h),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3.r),
                        child: LinearProgressIndicator(
                          value: pct,
                          backgroundColor: cs.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation(sub.color),
                          minHeight: 6.h,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecentActivity(ColorScheme cs) {
    final displayCount = _showAllActivity ? _activityHistory.length : 5;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recent Activity',
            style: GoogleFonts.atkinsonHyperlegible(
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
                color: cs.onSurface)),
        SizedBox(height: 12.h),
        Container(
          padding: EdgeInsets.symmetric(vertical: 8.h),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            children: [
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: displayCount,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, indent: 56.w, color: cs.outlineVariant),
                itemBuilder: (context, index) {
                  final act = _activityHistory[index];
                  return ListTile(
                    leading: CircleAvatar(
                      radius: 18.r,
                      backgroundColor: cs.surfaceContainerHighest,
                      child: Icon(
                        _iconForAction(act['action'] as String? ?? ''),
                        size: 18.sp,
                        color: cs.primary,
                      ),
                    ),
                    title: Text(_formatActivityTitle(act),
                        style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurface)),
                    trailing: Text(_formatRelativeTime(act['timestamp']),
                        style: TextStyle(
                            fontSize: 11.sp, color: cs.onSurfaceVariant)),
                    dense: true,
                  );
                },
              ),
              if (_activityHistory.length > 5)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
                  child: GestureDetector(
                    onTap: () => setState(() => _showAllActivity = !_showAllActivity),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _showAllActivity
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 20.sp,
                          color: cs.primary,
                        ),
                        SizedBox(width: 4.w),
                        Text(
                          _showAllActivity
                              ? 'Show Less'
                              : 'Show All (${_activityHistory.length})',
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w600,
                            color: cs.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SubjectTime {
  final String name;
  final int minutes;
  final Color color;
  const _SubjectTime(this.name, this.minutes, this.color);
}
