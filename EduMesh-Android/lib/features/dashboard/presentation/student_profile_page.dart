import 'dart:async';
import 'package:edumesh_android/core/navigation/lumina_transitions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:edumesh_android/core/constants/lumina_colors.dart';
import 'package:edumesh_android/core/constants/app_spacing.dart';
import 'package:edumesh_android/features/auth/data/auth_service.dart';
import '../../../core/services/activity_tracker.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/mutation_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';
import '../../../core/services/course_service.dart';
import 'course_player_page.dart';

import '../../auth/presentation/profile_picker_page.dart';

final _whitespaceRE = RegExp(r'\s+');

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
  String _username = '';
  String _studentId = '';
  String _grade = '';
  int _studyMinutesToday = 0;
  int _studyMinutesThisWeek = 0;
  int _streakDays = 0;
  int _coursesCompleted = 0;
  List<({String name, int minutes, Color color})> _subjectBreakdown = [];
  List<Map<String, dynamic>> _activityHistory = [];
  static const _subjectColors = [
    LuminaColors.academicTeal,
    LuminaColors.chartPurple,
    LuminaColors.chartEmerald,
    LuminaColors.chartCyan,
    LuminaColors.chartAmber,
    LuminaColors.danger,
  ];
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
    final name = await auth.getDisplayName() ?? await auth.getLoggedUsername();
    final uname = await auth.getLoggedUsername();
    final id = await auth.getUniqueUserId();
    final grade = await auth.getGradeOrDefault();
    if (mounted) {
      _studentId = id ?? _studentId;
      setState(() {
        _studentName = name ?? _studentName;
        _username = uname ?? _username;
        _grade = grade;
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
      // ponytail: sync() already cached fresh analytics when it synced, but
      // skips that GET when there are no pending events, so getAnalytics()
      // still runs to cover the online-with-no-events and offline paths.
      final analytics = await _tracker.getAnalytics();
      final history = await _tracker.getActivityHistory(limit: 50);
      if (mounted) {
        setState(() {
          _studyMinutesToday = ((analytics['study_minutes_today'] ?? 0) as num).toInt();
          _studyMinutesThisWeek = ((analytics['study_minutes_this_week'] ?? 0) as num).toInt();
          _streakDays = ((analytics['streak_days'] ?? 0) as num).toInt();
          final subjects = analytics['subjects'] as List<dynamic>? ?? [];
          _subjectBreakdown = subjects.map((s) => (
            name: s['name']?.toString() ?? '',
            minutes: ((s['minutes'] ?? 0) as num).toInt(),
            color: _colorForSubject(s['name']?.toString() ?? ''),
          )).toList();
          _activityHistory = history.where((a) => (a['action'] as String?) != 'study_session').toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
    try {
      _coursesCompleted = await CourseService().getCompletedCourseCount();
      await CourseService().loadEnrolledCourses();
      if (mounted) setState(() {});
    } catch (_) {}
    try {
      final profile = await ApiClient.get('/student/profile');
      if (mounted && profile.data is Map) {
        final p = profile.data as Map;
        _studentId = p['scholar_id']?.toString() ?? _studentId;
        setState(() {
          _studentName = p['name']?.toString() ?? _studentName;
          _grade = p['grade']?.toString() ?? _grade;
        });
        final name = p['name']?.toString();
        if (name != null && name.isNotEmpty) {
          AuthService().cacheDisplayName(name);
        }
        if (_username.isEmpty) {
          final whoami = await ApiClient.get('/whoami');
          if (whoami.data is Map) {
            final u = whoami.data['username']?.toString();
            if (u != null && u.isNotEmpty) {
              _username = u;
              AuthService().cacheUsername(u);
            }
          }
        }
        final scholarId = p['scholar_id']?.toString() ?? '';
        if (scholarId.isNotEmpty) {
          try {
            final iconResp = await ApiClient.dio.get(
              '/student/profile/icon/$scholarId',
              options: Options(responseType: ResponseType.bytes),
            );
            if (iconResp.statusCode == 200 && iconResp.data != null) {
              final bytes = Uint8List.fromList(List<int>.from(iconResp.data));
              if (bytes.isNotEmpty) {
                await _saveIconLocally(scholarId, bytes);
                final iconFile = File(await _iconPath(scholarId));
                if (mounted) setState(() => _profileImage = iconFile);
              }
            }
          } catch (_) { } }
      }
    } catch (_) { } }

  String _getInitials(String name, AppLocalizations l10n) {
    if (name.trim().isEmpty) return l10n.initialsFallback;
    final parts = name.trim().split(_whitespaceRE);
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  Color _colorForSubject(String name) {
    return _subjectColors[name.length % _subjectColors.length];
  }

  String _formatActivityTitle(Map<String, dynamic> activity, AppLocalizations l10n) {
    final action = (activity['action'] as String? ?? '').toLowerCase();
    if (action.isEmpty) return '';
    if (action == 'study_session') return _formatStudySessionTitle(activity, l10n);
    final verb = switch (action) {
      'view' => l10n.activityVerbViewed,
      'search' => l10n.activityVerbSearched,
      'download' => l10n.activityVerbDownloaded,
      'watch' => l10n.activityVerbWatched,
      'save' => l10n.activityVerbSaved,
      'open' => l10n.activityVerbOpened,
      'complete' => l10n.activityVerbCompleted,
      _ => '',
    };
    final meta = activity['metadata']?.toString() ?? '';
    final title = (meta.isNotEmpty && !meta.startsWith('{')) ? meta : '';
    if (title.isNotEmpty) return verb.isEmpty ? title : '$verb $title';
    if (verb.isEmpty) return '';
    return l10n.activityTitleFallback(verb);
  }

  /// Renders a study-session event as `Studied <subject> · <N> min`,
  /// or `Studied · <N> min` when the session has no subject.
  String _formatStudySessionTitle(Map<String, dynamic> activity, AppLocalizations l10n) {
    String subject = '';
    int minutes = 0;
    final meta = activity['metadata']?.toString() ?? '';
    if (meta.startsWith('{')) {
      try {
        final decoded = jsonDecode(meta);
        if (decoded is Map<String, dynamic>) {
          subject = decoded['subject']?.toString() ?? '';
          minutes = (((decoded['duration_seconds'] as num?) ?? 0) / 60).round();
        }
      } catch (_) {}
    }
    final studied = l10n.activityVerbStudied;
    final verb = studied.isNotEmpty
        ? '${studied[0].toUpperCase()}${studied.substring(1)}'
        : studied;
    final label = subject.isEmpty ? verb : '$verb $subject';
    return '$label · $minutes${l10n.studyReportMin}';
  }

  String _formatRelativeTime(dynamic timestamp, AppLocalizations l10n) {
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
    if (diff.inMinutes < 1) return l10n.relativeTimeJustNow;
    if (diff.inMinutes < 60) return l10n.relativeTimeMinutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return l10n.relativeTimeHoursAgo(diff.inHours);
    if (diff.inDays < 30) return l10n.relativeTimeDaysAgo(diff.inDays);
    return l10n.relativeTimeMonthsAgo(diff.inDays ~/ 30);
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
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _buildHeader(cs),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _loadData,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
                          // ponytail: builder defers offscreen sections on 1GB devices.
                      child: ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w),
                  itemCount: 12,
                  itemBuilder: (_, i) => switch (i) {
                    0 => _buildProfileCard(cs),
                    1 => SizedBox(height: AppSpacing.sm.h),
                    2 => _buildSwitchProfileTile(cs),
                    3 => SizedBox(height: AppSpacing.xl.h),
                    4 => _buildStatsRow(cs),
                    5 => SizedBox(height: AppSpacing.xxl.h),
                    6 => _buildMyCoursesSection(cs),
                    7 => SizedBox(height: AppSpacing.xxl.h),
                    8 => _buildSubjectBreakdown(cs),
                    9 => SizedBox(height: AppSpacing.xxl.h),
                    10 => _buildRecentActivity(cs),
                    _ => SizedBox(height: AppSpacing.xxl.h),
                  },
                          ),
                        ),
                      ),
                    ),
                ),
              ],
            ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs) {
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w, vertical: AppSpacing.sm.h),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(Icons.person_rounded, color: cs.primary, size: 24.sp),
          SizedBox(width: AppSpacing.md.w),
          Expanded(
            child: Text(l10n.headerMyProfile,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: tt.titleLarge?.copyWith(
                    color: cs.primary)),
          ),
          SizedBox(width: AppSpacing.sm.w),
          Icon(Icons.bar_chart_rounded, color: cs.primary, size: 20.sp),
          SizedBox(width: AppSpacing.xs.w),
          Text(l10n.headerAnalytics,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: tt.titleSmall?.copyWith(
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
    }
  }

  Widget _buildProfileCard(ColorScheme cs) {
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: EdgeInsets.only(top: AppSpacing.lg.h),
      padding: EdgeInsets.all(AppSpacing.xl.w),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm.r),
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
                      ? Text(_getInitials(_studentName, l10n),
                          style: tt.titleLarge?.copyWith(
                              color: cs.onPrimary))
                      : null,
                ),
                if (_uploadingIcon)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.scrim.withValues(alpha: 0.12),
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
          SizedBox(width: AppSpacing.lg.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_studentName,
                    style: tt.titleLarge?.copyWith(
                        color: cs.onSurface)),
                if (_username.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: AppSpacing.xs.h),
                    child: Text('@$_username',
                        style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant)),
                  ),
                SizedBox(height: AppSpacing.xs.h),
                Row(
                  children: [
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: AppSpacing.sm.w, vertical: AppSpacing.xs.h),
                      decoration: BoxDecoration(
                        color: LuminaColors.academicTeal.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4.r),
                      ),
                      child: Text(l10n.roleBadgeStudent,
                          style: tt.labelSmall?.copyWith(
                              color: LuminaColors.academicTeal,
                              fontWeight: AppSpacing.weightStrong)),
                    ),
                    SizedBox(width: AppSpacing.sm.w),
                    Text(_grade,
                        style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant)),
                  ],
                ),
                SizedBox(height: AppSpacing.xs.h),
                Text(_studentId,
                    style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant)),
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

  Widget _buildSwitchProfileTile(ColorScheme cs) {
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w, vertical: AppSpacing.xs.h),
        leading: Icon(Icons.switch_account_rounded, color: cs.primary),
        title: Text(l10n.switchProfileTitle,
            style: tt.bodyMedium?.copyWith(color: cs.onSurface, fontWeight: AppSpacing.weightStrong)),
        subtitle: Text(l10n.switchProfileSubtitle,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        trailing: Icon(Icons.chevron_right_rounded, color: cs.outline),
        onTap: () {
          Navigator.of(context).push(
            luminaRoute(builder: (_) => const ProfilePickerPage()),
          );
        },
      ),
    );
  }

  void _showEditProfileSheet(ColorScheme cs) {
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    final nameController = TextEditingController(text: _studentName);
    String selectedGrade = _grade.isNotEmpty ? _grade : 'General';
    void Function(void Function())? modalSetStateRef;
    List<String> availableGrades = [];
    bool loadingGrades = true;

    SharedPreferences.getInstance().then((prefs) {
      final cached = prefs.getStringList('cached_grades');
      if (cached != null && cached.isNotEmpty) {
        availableGrades = cached;
        loadingGrades = false;
        modalSetStateRef?.call(() {});
      }
    });

    ApiClient.get('/student/grades').then((res) async {
      if (res.data is List) {
        final grades = (res.data as List)
            .map((g) => (g as Map)['name']?.toString() ?? '')
            .where((n) => n.isNotEmpty)
            .toList();
        if (grades.isNotEmpty) {
          if (!grades.contains(selectedGrade)) {
            selectedGrade = grades.first;
          }
          availableGrades = grades;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setStringList('cached_grades', grades);
        } else {
          if (availableGrades.isEmpty) availableGrades = ['General'];
        }
      } else {
        if (availableGrades.isEmpty) availableGrades = ['General'];
      }
      loadingGrades = false;
      modalSetStateRef?.call(() {});
    });

    showLuminaSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, modalSetState) {
            modalSetStateRef = modalSetState;
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: Padding(
              padding: EdgeInsets.all(AppSpacing.xxl.w),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.edit_rounded, color: cs.primary, size: 22.sp),
                      SizedBox(width: AppSpacing.md.w),
                      Text(l10n.editProfileSheetTitle,
                          style: tt.titleLarge?.copyWith(
                              color: cs.primary)),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.close_rounded, size: 22.sp),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  SizedBox(height: AppSpacing.xl.h),
                  Text(l10n.editProfileLabelName,
                      style: tt.titleSmall?.copyWith(
                          color: cs.onSurfaceVariant)),
                  SizedBox(height: AppSpacing.sm.h),
                  TextField(
                    controller: nameController,
                    style: tt.bodyLarge?.copyWith(
                        color: cs.onSurface),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: cs.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.md.w, vertical: AppSpacing.md.h),
                    ),
                  ),
                  SizedBox(height: AppSpacing.lg.h),
                  Text(l10n.editProfileLabelGrade,
                      style: tt.titleSmall?.copyWith(
                          color: cs.onSurfaceVariant)),
                  SizedBox(height: AppSpacing.sm.h),
                  DropdownButtonFormField<String>(
                    initialValue: availableGrades.contains(selectedGrade) ? selectedGrade : null,
                    items: availableGrades.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                    onChanged: (v) { if (v != null) { selectedGrade = v; if (mounted) setState(() {}); } },
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: cs.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.md.w, vertical: AppSpacing.md.h),
                    ),
                    hint: loadingGrades
                        ? SizedBox(width: 16.sp, height: 16.sp, child: const CircularProgressIndicator(strokeWidth: 2))
                        : Text(l10n.editProfileGradeHint, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ),
                  SizedBox(height: AppSpacing.lg.h),
                  Text(l10n.editProfileLabelStudentId,
                      style: tt.titleSmall?.copyWith(
                          color: cs.onSurfaceVariant)),
                  SizedBox(height: AppSpacing.sm.h),
                  Text(_studentId,
                      style: tt.bodyLarge?.copyWith(
                          color: cs.onSurfaceVariant)),
                  SizedBox(height: AppSpacing.xxl.h),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final newName = nameController.text.trim();
                        if (newName.isNotEmpty || selectedGrade.isNotEmpty) {
                          final auth = AuthService();
                          if (newName.isNotEmpty) {
                            await auth.setDisplayName(newName);
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
                          unawaited(MutationQueue().enqueue('/student/profile/update', method: 'POST', body: {
                            if (newName.isNotEmpty) 'name': newName,
                            if (selectedGrade.isNotEmpty) 'grade': selectedGrade,
                          }));
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.md.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                      ),
                      child: Text(l10n.editProfileSaveButton,
                          style: tt.titleMedium?.copyWith(
                              color: cs.onPrimary, fontSize: 15.sp)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          );
        },
        );
      },
    ).then((_) {
      nameController.dispose();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Widget _buildStatsRow(ColorScheme cs) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm.r),
      ),
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.lg.w),
        child: Column(
          children: [
            _statRow(cs, l10n.statCardToday, '$_studyMinutesToday${l10n.suffixMinutes}', Icons.today_outlined, l10n.statCardThisWeek, _studyMinutesThisWeek < 60 ? '$_studyMinutesThisWeek${l10n.suffixMinutes}' : '${(_studyMinutesThisWeek / 60).toStringAsFixed(1)}${l10n.suffixHours}', Icons.date_range_outlined),
            SizedBox(height: AppSpacing.md.h),
            _statRow(cs, l10n.profileCoursesCompleted, '$_coursesCompleted', Icons.school_outlined, l10n.statCardStreak, '$_streakDays${l10n.suffixDays}', Icons.local_fire_department_outlined),
          ],
        ),
      ),
    );
  }

  Widget _statRow(ColorScheme cs, String label1, String value1, IconData icon1, String label2, String value2, IconData icon2) {
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(child: Row(children: [
          Icon(icon1, size: 20.sp, color: cs.primary),
          SizedBox(width: AppSpacing.sm.w),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value1, style: tt.titleLarge?.copyWith(color: cs.onSurface)),
            Text(label1, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ])),
        ])),
        SizedBox(width: AppSpacing.md.w),
        Expanded(child: Row(children: [
          Icon(icon2, size: 20.sp, color: cs.secondary),
          SizedBox(width: AppSpacing.sm.w),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value2, style: tt.titleLarge?.copyWith(color: cs.onSurface)),
            Text(label2, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ])),
        ])),
      ],
    );
  }

  Widget _buildMyCoursesSection(ColorScheme cs) {
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    final enrolled = CourseService().enrolledCourses;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.profileMyCourses,
            style: tt.titleLarge?.copyWith(color: cs.onSurface)),
        SizedBox(height: AppSpacing.xs.h),
        Text(l10n.profileTapToResume,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        SizedBox(height: AppSpacing.md.h),
        if (enrolled.isEmpty)
          Container(
            padding: EdgeInsets.all(AppSpacing.xl.w),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm.r),
            ),
            child: Center(
              child: Text(l10n.profileNoCourses,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm.r),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: enrolled.length,
              itemBuilder: (context, index) {
                final entry = enrolled[index];
                final progress = entry.progress;
                final total = (progress?['total_resources'] as num?)?.toInt() ?? 0;
                final completed = (progress?['completed_count'] as num?)?.toInt() ?? 0;
                final pct = total > 0 ? completed / total : 0.0;
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w, vertical: AppSpacing.md.h),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(entry.course.title,
                                maxLines: 2, overflow: TextOverflow.ellipsis,
                                style: tt.titleSmall?.copyWith(color: cs.onSurface)),
                            SizedBox(height: AppSpacing.sm.h),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3.r),
                              child: LinearProgressIndicator(
                                value: pct,
                                backgroundColor: cs.surfaceContainerHighest,
                                valueColor: AlwaysStoppedAnimation(cs.primary),
                                minHeight: 6.h,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: AppSpacing.md.w),
                      TextButton(
                        onPressed: () {
                          Navigator.push(context, luminaRoute(
                            builder: (_) => CoursePlayerPage(course: entry.course),
                          ));
                        },
                        child: Text(l10n.buttonContinue,
                            style: tt.labelSmall?.copyWith(color: cs.primary)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildSubjectBreakdown(ColorScheme cs) {
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    final total = _subjectBreakdown.fold(0, (sum, s) => sum + s.minutes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.sectionSubjectBreakdown,
            style: tt.titleLarge?.copyWith(
                color: cs.onSurface)),
          SizedBox(height: AppSpacing.md.h),
        Container(
          padding: EdgeInsets.all(AppSpacing.lg.w),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm.r),
          ),
          child: Column(
            children: [
              if (_subjectBreakdown.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg.h),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bar_chart_rounded, size: 24.sp, color: cs.onSurfaceVariant),
                        SizedBox(height: AppSpacing.xs.h),
                        Text(l10n.emptyStateSubjectBreakdown,
                            textAlign: TextAlign.center,
                            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
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
                final hours = '${(sub.minutes / 60).toStringAsFixed(1)}${l10n.suffixHours}';
                return Padding(
                  padding: EdgeInsets.only(bottom: i < _subjectBreakdown.length - 1 ? 14.h : 0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(sub.name,
                                style: tt.titleSmall?.copyWith(
                                    color: cs.onSurface)),
                          ),
                          Text(hours,
                              style: tt.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant)),
                          SizedBox(width: AppSpacing.sm.w),
                          Text('${(pct * 100).toStringAsFixed(0)}${l10n.suffixPercent}',
                              style: tt.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant)),
                        ],
                      ),
                      SizedBox(height: AppSpacing.sm.h),
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
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.sectionRecentActivity,
            style: tt.titleLarge?.copyWith(
                color: cs.onSurface)),
        SizedBox(height: AppSpacing.md.h),
        Container(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.sm.h),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm.r),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_activityHistory.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg.h),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history_rounded, size: 24.sp, color: cs.onSurfaceVariant),
                        SizedBox(height: AppSpacing.xs.h),
                        Text(l10n.emptyStateRecentActivity,
                            textAlign: TextAlign.center,
                            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                )
              else
                ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _activityHistory.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, indent: 56.w, color: cs.outlineVariant),
                itemBuilder: (context, index) {
                  final act = _activityHistory[index];
                  final title = _formatActivityTitle(act, l10n);
                  // Same guard as study_report_page: unmapped actions
                  // (e.g. 'unsave') format to '' and must not render.
                  if (title.isEmpty) return const SizedBox.shrink();
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
                    title: Text(title,
                        style: tt.bodySmall?.copyWith(
                            color: cs.onSurface)),
                    trailing: Text(_formatRelativeTime(act['timestamp'], l10n),
                        style: tt.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant)),
                    dense: true,
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
