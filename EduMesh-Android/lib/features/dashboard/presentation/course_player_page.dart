import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:edumesh_android/core/models/course.dart';
import 'package:edumesh_android/core/services/course_service.dart';
import 'package:edumesh_android/core/storage/db_helper.dart';
import 'package:edumesh_android/core/network/api_client.dart';
import 'package:edumesh_android/core/constants/lumina_colors.dart';
import 'package:edumesh_android/core/constants/app_spacing.dart';
import 'package:edumesh_android/shared/widgets/pdf_viewer_page.dart';
import 'package:edumesh_android/shared/widgets/video_player_page.dart';
import 'quiz_player_page.dart';

class CoursePlayerPage extends StatefulWidget {
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

      final progressRows = await db.query('course_progress',
        where: 'course_id = ?', whereArgs: [widget.course.id]);
      if (progressRows.isNotEmpty) {
        _currentPosition = (progressRows.first['current_position'] as num?)?.toInt() ?? 0;
      }

      final quizRows = await db.query('quiz_attempts',
        where: 'course_id = ? AND passed = 1', whereArgs: [widget.course.id]);
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
      debugPrint('CoursePlayerPage: _loadProgress failed — $e');
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
      await db.update('course_progress', {
        'completed_count': _completed.values.where((v) => v).length,
        'current_position': newPos,
      }, where: 'course_id = ?', whereArgs: [widget.course.id]);
    } catch (e) {
      debugPrint('CoursePlayerPage: _markCompleted failed — $e');
    }
  }

  Future<String> _resolveUrl(CourseResource resource) async {
    if (_localPaths.containsKey(resource.id)) return _localPaths[resource.id]!;
    await ApiClient.ensureInitialized();
    final base = ApiClient.dio.options.baseUrl.replaceAll(RegExp(r'/api/?$'), '');
    return '$base/files/${resource.filename ?? resource.id}';
  }

  void _openResource(CourseResource resource, int index) {
    if (!_isResourceUnlocked(index)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Complete the previous resource first')),
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
      if (resource.resourceType == CourseType.video) {
        unawaited(Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VideoPlayerPage(title: resource.title, videoUrl: url),
          ),
        ).then((_) => _markCompleted(resource.id)));
      } else {
        unawaited(Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PdfViewerPage(title: resource.title, pdfUrl: url),
          ),
        ).then((_) => _markCompleted(resource.id)));
      }
    });
  }

  Future<void> _downloadCourse() async {
    setState(() => _isDownloading = true);
    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 12),
            Text('Downloading course...'),
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
            const SnackBar(content: Text('Download failed. Check storage space.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        setState(() => _isDownloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: ${e.toString()}')),
        );
      }
    }
  }

  IconData _resourceIcon(CourseResource r) {
    switch (r.resourceType) {
      case CourseType.video: return Icons.play_circle_outline;
      case CourseType.quiz: return Icons.quiz_outlined;
      case CourseType.notes: return Icons.article_outlined;
      case CourseType.pastPaper: return Icons.folder_outlined;
      case CourseType.textbook: return Icons.menu_book_outlined;
    }
  }

  String _resourceTypeLabel(CourseResource r) {
    switch (r.resourceType) {
      case CourseType.video: return 'Video';
      case CourseType.quiz: return 'Quiz';
      case CourseType.notes: return 'Notes';
      case CourseType.pastPaper: return 'Past Paper';
      case CourseType.textbook: return 'Textbook';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(title: Text(widget.course.title)),
      body: Column(
        children: [
          if (_showDownloadPrompt && !_isDownloaded)
            _buildDownloadBanner(cs, tt),
          Expanded(
            child: _resources.isEmpty
              ? Center(
                  child: Text('No resources in this course',
                      style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
                )
              : ListView.builder(
                  padding: EdgeInsets.all(AppSpacing.lg.w),
                  itemCount: _resources.length,
                  itemBuilder: (ctx, i) => _buildResourceItem(i, cs, tt),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadBanner(ColorScheme cs, TextTheme tt) {
    return Container(
      width: double.infinity,
      color: cs.primaryContainer,
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w, vertical: AppSpacing.md.h),
      child: Row(
        children: [
          Expanded(
            child: Text('Download all resources to study offline',
                style: tt.bodyMedium?.copyWith(color: cs.onPrimaryContainer)),
          ),
          SizedBox(width: AppSpacing.md.w),
          FilledButton(
            onPressed: _isDownloading ? null : _downloadCourse,
            child: const Text('Download Course'),
          ),
        ],
      ),
    );
  }

  Widget _buildResourceItem(int index, ColorScheme cs, TextTheme tt) {
    final r = _resources[index];
    final unlocked = _isResourceUnlocked(index);
    final completed = _completed[r.id] == true;
    final isCurrent = index == _currentPosition && !completed;

    return Card(
      margin: EdgeInsets.only(bottom: AppSpacing.md.h),
      color: completed
          ? cs.primaryContainer.withValues(alpha: 0.3)
          : isCurrent
              ? cs.primaryContainer.withValues(alpha: 0.18)
              : unlocked
                  ? cs.surfaceContainerLow
                  : cs.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Opacity(
        opacity: unlocked ? 1.0 : 0.6,
        child: ListTile(
          leading: Icon(
            completed
                ? Icons.check_circle
                : unlocked
                    ? _resourceIcon(r)
                    : Icons.lock_outline,
            color: completed
                ? LuminaColors.successGreen
                : unlocked
                    ? cs.primary
                    : cs.onSurfaceVariant,
            size: 28.sp,
          ),
          title: Text(r.title, style: tt.titleSmall?.copyWith(color: cs.onSurface)),
          subtitle: Text(
            completed
                ? 'Completed'
                : unlocked
                    ? _resourceTypeLabel(r)
                    : 'Locked',
            style: tt.bodySmall?.copyWith(
              color: completed
                  ? LuminaColors.successGreen
                  : cs.onSurfaceVariant,
            ),
          ),
          trailing: completed
              ? Icon(Icons.check_circle, color: LuminaColors.successGreen, size: 24.sp)
              : unlocked
                  ? FilledButton(
                      onPressed: () => _openResource(r, index),
                      child: const Text('Start'),
                    )
                  : Icon(Icons.lock, color: cs.onSurfaceVariant, size: 20.sp),
          onTap: unlocked ? () => _openResource(r, index) : null,
        ),
      ),
    );
  }
}
