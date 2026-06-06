import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:edumesh_android/core/constants/lumina_colors.dart';
import 'package:edumesh_android/core/constants/app_spacing.dart';
import 'package:edumesh_android/features/auth/data/auth_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../core/services/activity_tracker.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/network/api_client.dart';

/// The student profile and analytics page.
///
/// Displays the user's name, grade, student ID, profile icon, study stats
/// (today / week / saved / streak), a subject-breakdown bar chart, and a
/// recent-activity timeline. Profile data is loaded from [AuthService] first
/// (offline-capable) then refreshed from the server. The profile icon is
/// persisted to the app documents directory for offline display.
class StudentProfilePage extends StatefulWidget {
  const StudentProfilePage({super.key});

  /// Creates the state for the [StudentProfilePage].
  @override
  State<StudentProfilePage> createState() => _StudentProfilePageState();
}

class _StudentProfilePageState extends State<StudentProfilePage> {
  final ActivityTracker _tracker = ActivityTracker();
  String _studentName = '';
  String _studentId = '';
  String _grade = '';
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
    _loadLocalProfile();
    _loadData();
  }

  /// The persistent file path for a scholar's profile icon.
  ///
  /// Stores the icon under `{appDocumentsDir}/profile_icons/{scholarId}_icon.png`
  /// so it survives app restarts and is available offline.
  Future<String> _iconPath(String scholarId) async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/profile_icons/${scholarId}_icon.png';
  }

  /// Persists profile icon bytes to local storage.
  ///
  /// Creates the `profile_icons/` directory if needed and writes the decoded
  /// image data to the path returned by [_iconPath].
  Future<void> _saveIconLocally(String scholarId, Uint8List bytes) async {
    final path = await _iconPath(scholarId);
    final file = File(path);
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  /// Loads cached profile fields and icon from local storage.
  ///
  /// Reads [AuthService] for the cached name, id, and grade so the profile
  /// card is populated immediately even when offline. Also checks for a
  /// previously saved icon at [_iconPath] and displays it if found.
  Future<void> _loadLocalProfile() async {
    final auth = AuthService();
    final name = await auth.getLoggedUsername();
    final id = await auth.getUniqueUserId();
    final grade = await auth.getStudentGrade();
    if (mounted) {
      setState(() {
        _studentName = name ?? _studentName;
        _studentId = id ?? _studentId;
        _grade = grade ?? _grade;
      });
    }
    if (id != null && id.isNotEmpty) {
      final iconFile = File(await _iconPath(id));
      if (await iconFile.exists()) {
        if (mounted) setState(() => _profileImage = iconFile);
      }
    }
  }

  /// Fetches analytics and profile data from the server.
  ///
  /// Calls [ActivityTracker.sync], then retrieves analytics and activity history.
  /// Separately fetches `/student/profile` for name, scholar id, and grade, and
  /// `/student/profile/icon/{id}` for the profile picture. Server responses
  /// override the local defaults set by [_loadLocalProfile]. The fetched icon
  /// is saved to persistent storage via [_saveIconLocally].
  Future<void> _loadData() async {
    await _tracker.sync();
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
    try {
      final profile = await ApiClient.get('/student/profile');
      if (mounted && profile.data is Map) {
        final p = profile.data as Map;
        setState(() {
          _studentName = p['name']?.toString() ?? _studentName;
          _studentId = p['scholar_id']?.toString() ?? _studentId;
          _grade = p['grade']?.toString() ?? _grade;
        });
        final scholarId = p['scholar_id']?.toString() ?? '';
        if (scholarId.isNotEmpty) {
          try {
            final iconResponse = await ApiClient.get('/student/profile/icon/$scholarId');
            if (iconResponse.statusCode == 200 && iconResponse.data != null) {
              final bytes = iconResponse.data is List<int>
                  ? Uint8List.fromList(List<int>.from(iconResponse.data))
                  : Uint8List(0);
              if (bytes.isNotEmpty) {
                await _saveIconLocally(scholarId, bytes);
                final iconFile = File(await _iconPath(scholarId));
                if (mounted) {
                  setState(() => _profileImage = iconFile);
                }
              }
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  String _getInitials(String name) {
    if (name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
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
    final title = activity['resource_title']?.toString() ?? activity['title']?.toString() ?? '';
    if (title.isNotEmpty) return '$verb $title';
    return '$verb a resource';
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
      case 'save':
        return Icons.bookmark_rounded;
      case 'open':
        return Icons.open_in_new_rounded;
      case 'complete':
        return Icons.check_circle_rounded;
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
                    child: RefreshIndicator(
                      onRefresh: _loadData,
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
                ),
              ],
            ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w, vertical: AppSpacing.sm.h),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant, width: 1)),
      ),
      child: Row(
        children: [
          Icon(Icons.person_rounded, color: cs.primary, size: 24.sp),
          SizedBox(width: AppSpacing.md.w),
          Text('My Profile',
              style: GoogleFonts.atkinsonHyperlegible(
                  fontSize: 20.sp,
                  fontWeight: AppSpacing.weightDisplay,
                  color: cs.primary)),
          const Spacer(),
          Icon(Icons.bar_chart_rounded, color: cs.primary, size: 20.sp),
          SizedBox(width: AppSpacing.xs.w),
          Text('Analytics',
              style: GoogleFonts.atkinsonHyperlegible(
                  fontSize: 13.sp,
                  fontWeight: AppSpacing.weightStrong,
                  color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  /// Opens the image picker and uploads the selected icon to the server.
  ///
  /// Picks a square image (max 256px) from the gallery, base64-encodes it,
  /// and sends it to `POST /student/profile/icon`. On success the icon is
  /// persisted locally via [_saveIconLocally] and displayed immediately.
  /// Acquires a [WakelockPlus] wakelock during upload to prevent sleep.
  Future<void> _pickAndUploadIcon() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 256, maxHeight: 256);
    if (picked == null) return;
    setState(() => _uploadingIcon = true);
    await WakelockPlus.enable();
    try {
      final bytes = await picked.readAsBytes();
      final b64 = base64Encode(bytes);
      final ext = picked.path.split('.').last;
      final scholarId = await AuthService().getUniqueUserId();
      if (scholarId == null) {
        await WakelockPlus.disable();
        if (mounted) setState(() => _uploadingIcon = false);
        return;
      }
      await ApiClient.post('/student/profile/icon', data: {
        'image_data': b64,
        'image_ext': ext,
      });
      await _saveIconLocally(scholarId, bytes);
      final iconFile = File(await _iconPath(scholarId));
      if (mounted) {
        setState(() {
          _profileImage = iconFile;
          _uploadingIcon = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _uploadingIcon = false);
    } finally {
      await WakelockPlus.disable();
    }
  }

  Widget _buildProfileCard(ColorScheme cs) {
    return Container(
      margin: EdgeInsets.only(top: AppSpacing.lg.h),
      padding: EdgeInsets.all(AppSpacing.xl.w),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg.r),
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
                      ? Text(_getInitials(_studentName),
                          style: GoogleFonts.atkinsonHyperlegible(
                              fontSize: 22.sp,
                              fontWeight: AppSpacing.weightStrong,
                              color: cs.onPrimary))
                      : null,
                ),
                if (_uploadingIcon)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.scrim.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: SizedBox(
                          width: 20.sp,
                          height: 20.sp,
                          child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: EdgeInsets.all(AppSpacing.xs.w),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.camera_alt, size: 12.sp, color: cs.onPrimary),
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
                        fontWeight: AppSpacing.weightStrong,
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
                              fontWeight: AppSpacing.weightStrong)),
                    ),
                    SizedBox(width: 8.w),
                    Text(_grade,
                        style: TextStyle(
                            fontSize: 13.sp,
                            color: cs.onSurfaceVariant,
                            fontWeight: AppSpacing.weightBody)),
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
    String selectedGrade = _grade;
    List<String> availableGrades = [];
    bool loadingGrades = true;

    ApiClient.get('/grades').then((res) {
      if (res.data is List) {
        final grades = (res.data as List)
            .map((g) => (g is Map ? g['name']?.toString() ?? '' : g.toString()))
            .where((n) => n.isNotEmpty)
            .toList();
        if (grades.isNotEmpty && !grades.contains(selectedGrade)) {
          selectedGrade = grades[0];
        }
        availableGrades = grades;
      }
      loadingGrades = false;
      if (mounted) setState(() {});
    });

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
                              fontWeight: AppSpacing.weightStrong,
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
                          fontWeight: AppSpacing.weightStrong,
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
                          fontWeight: AppSpacing.weightStrong,
                          color: cs.onSurfaceVariant)),
                  SizedBox(height: 6.h),
                  DropdownButtonFormField<String>(
                    initialValue: availableGrades.contains(selectedGrade) ? selectedGrade : null,
                    items: availableGrades.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                    onChanged: (v) => selectedGrade = v ?? selectedGrade,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: cs.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                    ),
                    hint: loadingGrades
                        ? SizedBox(width: 16.sp, height: 16.sp, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text('Select grade', style: TextStyle(color: cs.onSurfaceVariant)),
                  ),
                  SizedBox(height: 16.h),
                  Text('Student ID',
                      style: GoogleFonts.atkinsonHyperlegible(
                          fontSize: 13.sp,
                          fontWeight: AppSpacing.weightStrong,
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
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final newName = nameController.text.trim();
                        if (newName.isNotEmpty || selectedGrade.isNotEmpty) {
                          try {
                            await ApiClient.post('/student/profile/update', data: {
                              if (newName.isNotEmpty) 'name': newName,
                              if (selectedGrade.isNotEmpty) 'grade': selectedGrade,
                            });
                            final auth = AuthService();
                            if (newName.isNotEmpty) {
                              await auth.saveUsername(newName);
                            }
                            if (selectedGrade.isNotEmpty) {
                              await auth.saveGrade(selectedGrade);
                            }
                            if (mounted) {
                              setState(() {
                                _studentName = newName.isNotEmpty ? newName : _studentName;
                                _grade = selectedGrade.isNotEmpty ? selectedGrade : _grade;
                              });
                              if (ctx.mounted) Navigator.pop(ctx);
                            }
                          } catch (e) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('Failed to update profile: $e')),
                            );
                          }
                        }
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
                              fontWeight: AppSpacing.weightStrong)),
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
    });
  }

  Widget _buildStatsRow(ColorScheme cs) {
    return Row(
      children: [
        Expanded(child: _buildStatCard(cs, 'Today', '${_studyMinutesToday}m', Icons.today_rounded, LuminaColors.academicTeal)),
        SizedBox(width: 10.w),
        Expanded(child: _buildStatCard(cs, 'This Week', _studyMinutesThisWeek < 60 ? '${_studyMinutesThisWeek}m' : '${(_studyMinutesThisWeek / 60).toStringAsFixed(1)}h', Icons.date_range_rounded, const Color(0xFF7C3AED))),
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
                  fontWeight: AppSpacing.weightStrong,
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
                fontWeight: AppSpacing.weightStrong,
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
              if (_subjectBreakdown.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.h),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.bar_chart_rounded, size: 36.sp, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                        SizedBox(height: 8.h),
                        Text('No study data yet.\nYour subject time will appear here as you use the app.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13.sp, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                )
              else
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
                                    fontWeight: AppSpacing.weightStrong,
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
                fontWeight: AppSpacing.weightStrong,
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
              if (_activityHistory.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 32.h),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.history_rounded, size: 40.sp, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                        SizedBox(height: 12.h),
                        Text('No recent activity yet.\nStart browsing resources to see your activity here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13.sp, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                )
              else
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
                            fontWeight: AppSpacing.weightBody,
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
                            fontWeight: AppSpacing.weightStrong,
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
