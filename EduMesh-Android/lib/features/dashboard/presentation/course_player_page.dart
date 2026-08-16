import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:edumesh_android/core/models/course.dart';
import 'package:edumesh_android/core/models/resource_model.dart';
import 'package:edumesh_android/core/services/course_service.dart';
import 'package:edumesh_android/core/storage/db_helper.dart';
import 'package:edumesh_android/core/network/api_client.dart';
import 'package:edumesh_android/core/constants/lumina_colors.dart';
import 'package:edumesh_android/core/constants/app_spacing.dart';
import 'package:edumesh_android/shared/widgets/pdf_viewer_page.dart';
import 'package:edumesh_android/shared/widgets/video_player_page.dart';
import 'package:edumesh_android/shared/widgets/resource_thumbnail.dart';
import 'package:edumesh_android/core/services/recent_resources.dart';
import 'package:edumesh_android/features/auth/data/auth_service.dart';
import 'quiz_player_page.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';

/// Plays a course's resources in order, unlocking each one after the previous
/// is completed and marking progress in the local database.
class CoursePlayerPage extends StatefulWidget {
  /// The course to play through.
  final Course course;

  const CoursePlayerPage({super.key, required this.course});

  @override
  State<CoursePlayerPage> createState() => _CoursePlayerPageState();
}

class _CoursePlayerPageState extends State<CoursePlayerPage> {
  List<CourseResource> _resources = [];
  final Map<String, bool> _completed = {};
  int _currentPosition = 0;
  bool _isDownloaded = false;
  bool _isDownloading = false;
  bool _showDownloadPrompt = true;
  Map<String, String> _localPaths = {};

  @override
  void initState() {
    super.initState();
    _resources = widget.course.resources ?? [];
    _resources.sort((a, b) => a.position.compareTo(b.position));
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    try {
      final db = await DBHelper().database;
      final studentId = (await AuthService().getUniqueUserId()) ?? '';

      final progressRows = await db.query('course_progress',
        where: 'course_id = ? AND student_id = ?', whereArgs: [widget.course.id, studentId]);
      if (progressRows.isNotEmpty) {
        _currentPosition = (progressRows.first['current_position'] as num?)?.toInt() ?? 0;
      }

      final quizRows = await db.query('quiz_attempts',
        where: 'course_id = ? AND student_id = ? AND passed = 1', whereArgs: [widget.course.id, studentId]);
      final passedQuizIds = quizRows
        .map((r) => r['resource_id']?.toString() ?? '')
        .toSet();

      for (final r in _resources) {
        if (r.isQuiz) {
          if (passedQuizIds.contains(r.id)) _completed[r.id] = true;
        } else {
          if (r.position < _currentPosition) _completed[r.id] = true;
        }
      }

      final dlResources = await DBHelper().getDownloadedResources();
      final dlIds = dlResources.map((d) => d['resource_id']?.toString() ?? '').toSet();
      final pathMap = <String, String>{};
      for (final d in dlResources) {
        final rid = d['resource_id']?.toString() ?? '';
        final path = d['local_path'] as String?;
        if (rid.isNotEmpty && path != null && path.isNotEmpty) {
          pathMap[rid] = path;
        }
      }

      if (mounted) {
        setState(() {
          _localPaths = pathMap;
          _isDownloaded = _resources.every((r) => dlIds.contains(r.id));
          if (_isDownloaded) _showDownloadPrompt = false;
        });
      }
    } catch (e) {
      debugPrint('CoursePlayerPage: _loadProgress failed -- $e');
    }
  }

  bool _isResourceUnlocked(int index) {
    if (index == 0) return true;
    final prev = _resources[index - 1];
    return _completed[prev.id] == true;
  }

  Future<void> _markCompleted(String resourceId) async {
    _completed[resourceId] = true;
    int newPos = _currentPosition;
    for (int i = 0; i < _resources.length; i++) {
      if (_completed[_resources[i].id] != true) {
        newPos = i;
        break;
      }
    }
    if (newPos >= _resources.length) newPos = _resources.length;
    _currentPosition = newPos;
    if (mounted) setState(() {});
    try {
      final db = await DBHelper().database;
      final studentId = (await AuthService().getUniqueUserId()) ?? '';
      await db.update('course_progress', {
        'completed_count': _completed.values.where((v) => v).length,
        'current_position': newPos,
      }, where: 'course_id = ? AND student_id = ?', whereArgs: [widget.course.id, studentId]);
    } catch (e) {
      debugPrint('CoursePlayerPage: _markCompleted failed -- $e');
    }
  }

  Future<String> _resolveUrl(CourseResource resource) async {
    if (_localPaths.containsKey(resource.id)) return _localPaths[resource.id]!;
    await ApiClient.ensureInitialized();
    final base = ApiClient.fileBaseUrl;
    if (resource.filename != null && resource.filename!.contains('/')) {
      return '$base/files/${resource.filename}';
    }
    return '$base/files/courses/${resource.courseId}/resources/${resource.filename ?? resource.id}';
  }

  void _openResource(CourseResource resource, int index) {
    final l10n = AppLocalizations.of(context)!;
    if (!_isResourceUnlocked(index)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.coursePlayerLocked)),
      );
      return;
    }
    if (resource.isQuiz) {
      unawaited(Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QuizPlayerPage(
            course: widget.course,
            resource: resource,
            onComplete: () => _markCompleted(resource.id),
          ),
        ),
      ));
      return;
    }
    _resolveUrl(resource).then((url) {
      if (!mounted) return;
      unawaited(RecentResources.record(resource.id, resource.title, resource.resourceType.name));
      if (resource.resourceType == CourseType.video) {
        unawaited(Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VideoPlayerPage(title: resource.title, videoUrl: url, subject: widget.course.subject),
          ),
        ).then((_) => _markCompleted(resource.id)));
      } else {
        unawaited(Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PdfViewerPage(title: resource.title, pdfUrl: url, subject: widget.course.subject),
          ),
        ).then((_) => _markCompleted(resource.id)));
      }
    });
  }

  Future<void> _downloadCourse() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _isDownloading = true);
    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            SizedBox(width: AppSpacing.md.w),
            Text(l10n.coursePlayerDownloading),
          ],
        ),
      ),
    ));
    try {
      final success = await CourseService().downloadCourse(widget.course.id, _resources);
      if (mounted) {
        Navigator.of(context).pop();
        if (success) {
          setState(() {
            _isDownloaded = true;
            _isDownloading = false;
            _showDownloadPrompt = false;
          });
        } else {
          setState(() => _isDownloading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.coursePlayerDownloadFailed)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        setState(() => _isDownloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.coursePlayerDownloadFailed)),
        );
      }
    }
  }

  String _resourceTypeLabel(CourseResource r, AppLocalizations l10n) {
    switch (r.resourceType) {
      case CourseType.video: return l10n.coursePlayerVideo;
      case CourseType.quiz: return l10n.coursePlayerQuiz;

      case CourseType.pastPaper: return l10n.coursePlayerPastPaper;
      case CourseType.textbook: return l10n.coursePlayerTextbook;
    }
  }

  /// Maps a course resource type to the shared catalog [ResourceType].
  ResourceType _toResourceType(CourseType t) {
    switch (t) {
      case CourseType.video: return ResourceType.videos;
      case CourseType.quiz: return ResourceType.quiz;
      case CourseType.pastPaper: return ResourceType.pastPaper;
      case CourseType.textbook: return ResourceType.textbook;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(widget.course.title),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
      ),
      body: Column(
        children: [
          if (_showDownloadPrompt && !_isDownloaded)
            _buildDownloadBanner(cs, tt, l10n),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
                child: _resources.isEmpty
                  ? Center(
                      child: Text(l10n.coursePlayerNoResources,
                          style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.all(AppSpacing.lg.w),
                      itemCount: _resources.length,
                      itemBuilder: (ctx, i) => _buildResourceItem(i, cs, tt, l10n),
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadBanner(ColorScheme cs, TextTheme tt, AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      color: cs.primaryContainer,
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w, vertical: AppSpacing.md.h),
      child: Row(
        children: [
          Expanded(
            child: Text(l10n.coursePlayerDownloadPrompt,
                style: tt.bodyMedium?.copyWith(color: cs.onPrimaryContainer)),
          ),
          SizedBox(width: AppSpacing.md.w),
          FilledButton(
            onPressed: _isDownloading ? null : _downloadCourse,
            child: Text(l10n.coursePlayerDownloadButton),
          ),
        ],
      ),
    );
  }

  Widget _buildResourceItem(int index, ColorScheme cs, TextTheme tt, AppLocalizations l10n) {
    final r = _resources[index];
    final unlocked = _isResourceUnlocked(index);
    final completed = _completed[r.id] == true;
    final isCurrent = index == _currentPosition && !completed;

    return ResourceCard(
      resourceId: r.id,
      title: r.title,
      type: _toResourceType(r.resourceType),
      fileSize: r.fileSize,
      pageCount: r.pageCount,
      durationSeconds: r.durationSeconds,
      subtitle: completed
          ? l10n.coursePlayerCompleted
          : unlocked
              ? _resourceTypeLabel(r, l10n)
              : l10n.coursePlayerLocked,
      isReady: _localPaths.containsKey(r.id),
      opacity: unlocked ? 1.0 : 0.6,
      backgroundColor: completed
          ? cs.primaryContainer
          : isCurrent
              ? cs.surfaceContainerHigh
              : unlocked
                  ? cs.surfaceContainerLow
                  : cs.surfaceContainerHighest,
      trailing: completed
          ? Icon(Icons.check_circle, color: LuminaColors.successGreen, size: 24.sp)
          : unlocked
              ? FilledButton(
                  onPressed: () => _openResource(r, index),
                  child: Text(l10n.coursePlayerStart),
                )
              : Icon(Icons.lock, color: cs.onSurfaceVariant, size: 20.sp),
      onTap: unlocked ? () => _openResource(r, index) : null,
    );
  }
}
