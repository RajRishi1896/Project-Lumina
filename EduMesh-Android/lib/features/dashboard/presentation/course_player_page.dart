import 'dart:async';
import 'package:edumesh_android/core/navigation/lumina_transitions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:edumesh_android/core/models/course.dart';
import 'package:edumesh_android/core/models/resource_model.dart';
import 'package:edumesh_android/core/services/bookmark_sync.dart';
import 'package:edumesh_android/core/services/course_service.dart';
import 'package:edumesh_android/core/services/mutation_queue.dart';
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
  List<CourseTopic> _topics = [];
  final Map<String, bool> _completed = {};
  Set<String> _unlocked = {};
  int _currentPosition = 0;
  bool _isDownloaded = false;
  bool _isDownloading = false;
  Map<String, String> _localPaths = {};
  bool _loadingResources = true;
  bool _loadFailedResources = false;
  bool _isCourseSaved = false;

  @override
  void initState() {
    super.initState();
    _loadResources();
    _loadSavedState();
  }

  /// Reads whether this course is bookmarked (type `course` rows only, so a
  /// resource sharing the id can never flip the icon).
  Future<void> _loadSavedState() async {
    try {
      final rows = await DBHelper().getBookmarkedResources();
      if (!mounted) return;
      setState(() => _isCourseSaved = rows.any((r) =>
          (r['resource_id'] ?? '').toString() == widget.course.id &&
          (r['type'] ?? '').toString() == 'course'));
    } catch (_) {}
  }

  /// Saves/unsaves this course in the local `bookmarks` table as type `course`.
  Future<void> _toggleCourseSave() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    try {
      final db = DBHelper();
      final wasSaved = _isCourseSaved;
      if (wasSaved) {
        await db.removeBookmark(widget.course.id);
      } else {
        await db.upsertBookmark(widget.course.id, widget.course.title,
            widget.course.subject, widget.course.grade.toString(), 'course');
      }
      if (mounted) setState(() => _isCourseSaved = !wasSaved);
      unawaited(BookmarkSync.push());
      if (mounted) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(
          content: Text(wasSaved ? l10n.snackbarRemovedFromSaved : l10n.snackbarAddedToSaved),
          duration: const Duration(milliseconds: 600),
        ));
      }
    } catch (_) {}
  }

  /// Loads the course's detail: server first, local cache as offline
  /// fallback, then refreshes progress against the loaded list. Topics and
  /// resources come from the same payload so locks work fully offline.
  Future<void> _loadResources() async {
    // Show whatever the navigation path already carried while fetching.
    final initial = widget.course.resources;
    if (initial != null && initial.isNotEmpty) {
      if (mounted) {
        setState(() {
          _resources = [...initial]..sort((a, b) => a.position.compareTo(b.position));
          _topics = [...?widget.course.topics]..sort((a, b) => a.position.compareTo(b.position));
          _unlocked = computeUnlockedResourceIds(
              topics: _topics, resources: _resources, completedIds: const {});
        });
      }
    } else if (widget.course.topics != null && widget.course.topics!.isNotEmpty) {
      if (mounted) {
        setState(() => _topics = [...widget.course.topics!]..sort((a, b) => a.position.compareTo(b.position)));
      }
    }
    try {
      final detail = await CourseService().fetchCourseDetail(widget.course.id);
      List<CourseResource> loaded = const [];
      List<CourseTopic> topics = const [];
      if (detail != null && detail['resources'] is List) {
        loaded = (detail['resources'] as List)
            .whereType<Map>()
            .map((e) => CourseResource.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        if (detail['topics'] is List) {
          topics = (detail['topics'] as List)
              .whereType<Map>()
              .map((e) => CourseTopic.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      } else {
        final cached = await CourseService().getCachedCourseDetail(widget.course.id);
        if (cached != null) {
          if (cached['resources'] is List) {
            loaded = (cached['resources'] as List)
                .whereType<Map>()
                .map((e) => CourseResource.fromJson(Map<String, dynamic>.from(e)))
                .toList();
          }
          if (cached['topics'] is List) {
            topics = (cached['topics'] as List)
                .whereType<Map>()
                .map((e) => CourseTopic.fromJson(Map<String, dynamic>.from(e)))
                .toList();
          }
        }
      }
      loaded.sort((a, b) => a.position.compareTo(b.position));
      topics.sort((a, b) => a.position.compareTo(b.position));
      if (!mounted) return;
      setState(() {
        if (loaded.isNotEmpty) _resources = loaded;
        _topics = topics;
        _loadingResources = false;
        _loadFailedResources = _resources.isEmpty;
      });
      await _loadProgress();
    } catch (e) {
      debugPrint('CoursePlayerPage: _loadResources failed; $e');
      if (!mounted) return;
      setState(() {
        _loadingResources = false;
        _loadFailedResources = true;
      });
    }
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
      _unlocked = computeUnlockedResourceIds(
        topics: _topics,
        resources: _resources,
        completedIds: _completed.entries.where((e) => e.value).map((e) => e.key).toSet(),
      );

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
          // Mark as downloaded when ALL resources have local files, OR when
          // the course has existing progress (user already opened it before).
          _isDownloaded = _resources.every((r) => dlIds.contains(r.id))
              || (_currentPosition > 0 && _localPaths.isNotEmpty);
        });
      }
      // Keep total_resources equal to the live resource count so progress
      // fractions (completed/total) stay meaningful after content updates.
      try {
        await db.update('course_progress', {'total_resources': _resources.length},
            where: 'course_id = ? AND student_id = ?',
            whereArgs: [widget.course.id, studentId]);
      } catch (_) {}
    } catch (e) {
      debugPrint('CoursePlayerPage: _loadProgress failed; $e');
    }
  }

  bool _isResourceUnlocked(CourseResource r) => _unlocked.contains(r.id);

  /// Whether [r]'s chapter is locked by an incomplete previous chapter
  /// (as opposed to a sequential lock inside its own unlocked chapter).
  /// Ungrouped resources are never chapter-locked.
  bool _isChapterLocked(CourseResource r) {
    if (r.topicId.isEmpty) return false;
    final sorted = [..._topics]..sort((a, b) => a.position.compareTo(b.position));
    final idx = sorted.indexWhere((t) => t.id == r.topicId);
    if (idx <= 0) return false;
    final done = _completed.entries.where((e) => e.value).map((e) => e.key).toSet();
    for (var pj = 0; pj < idx; pj++) {
      final prev = _resources.where((x) => x.topicId == sorted[pj].id);
      if (prev.any((x) => !done.contains(x.id))) return true;
    }
    return false;
  }

  Future<void> _markCompleted(String resourceId) async {
    _completed[resourceId] = true;
    _unlocked = computeUnlockedResourceIds(
      topics: _topics,
      resources: _resources,
      completedIds: _completed.entries.where((e) => e.value).map((e) => e.key).toSet(),
    );
    int newPos = _currentPosition;
    for (int i = 0; i < _resources.length; i++) {
      if (_completed[_resources[i].id] != true) {
        newPos = i;
        break;
      }
    }
    if (newPos >= _resources.length) newPos = _resources.length;
    final doneCount = _completed.values.where((v) => v).length;
    final allDone = _resources.isNotEmpty && doneCount == _resources.length;
    _currentPosition = newPos;
    if (mounted) setState(() {});
    try {
      final db = await DBHelper().database;
      final studentId = (await AuthService().getUniqueUserId()) ?? '';
      await db.update('course_progress', {
        'completed_count': doneCount,
        'total_resources': _resources.length,
        'current_position': newPos,
        if (allDone) 'completed': 1,
      }, where: 'course_id = ? AND student_id = ?', whereArgs: [widget.course.id, studentId]);
      // Sync progress upstream (offline-safe: queued when unreachable).
      await MutationQueue().enqueue(
        '/api/courses/${widget.course.id}/progress',
        method: 'put',
        body: {
          'current_position': newPos,
          'completed_count': doneCount,
          'total_resources': _resources.length,
          if (allDone) 'completed': true,
        },
      );
    } catch (e) {
      debugPrint('CoursePlayerPage: _markCompleted failed; $e');
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

  void _openResource(CourseResource resource) {
    final l10n = AppLocalizations.of(context)!;
    if (!_isResourceUnlocked(resource)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isChapterLocked(resource)
              ? l10n.coursePlayerChapterLocked
              : l10n.coursePlayerLocked),
        ),
      );
      return;
    }
    if (resource.isQuiz) {
      // Quiz completes only on a server-graded pass: QuizPlayerPage calls
      // onComplete solely when the graded verdict passed.
      unawaited(Navigator.push(
        context,
        luminaRoute(
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
        // Video completes on the playback-ended event, not on close.
        unawaited(Navigator.push(
          context,
          luminaRoute(
            builder: (_) => VideoPlayerPage(
              title: resource.title,
              videoUrl: url,
              subject: widget.course.subject,
              onEnded: () => _markCompleted(resource.id),
            ),
          ),
        ));
      } else if (resource.resourceType == CourseType.textbook ||
          resource.resourceType == CourseType.pastPaper) {
        // PDF completes when the last page is reached.
        unawaited(Navigator.push(
          context,
          luminaRoute(
            builder: (_) => PdfViewerPage(
              title: resource.title,
              pdfUrl: url,
              subject: widget.course.subject,
              onLastPage: () => _markCompleted(resource.id),
            ),
          ),
        ));
      } else {
        // Other types complete on open.
        _markCompleted(resource.id);
      }
    });
  }

  Future<void> _downloadCourse() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _isDownloading = true);
    unawaited(showLuminaDialog(
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

  /// Confirms unenrollment in plain language, clears local enrollment state,
  /// reloads the enrolled lists, and leaves the player on success.
  Future<void> _confirmUnenroll() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showLuminaDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.unenrollDialogTitle),
        content: Text(l10n.unenrollDialogBody(widget.course.title)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.buttonCancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.unenrollButton)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await CourseService().unenroll(widget.course.id);
    if (!mounted) return;
    if (ok) {
      await CourseService().loadEnrolledCourses();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.unenrollSuccess(widget.course.title))));
      Navigator.of(context).pop();
    } else {
      messenger.showSnackBar(SnackBar(content: Text(l10n.unenrollFailed)));
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
        actions: [
          IconButton(
            icon: Icon(_isCourseSaved ? Icons.bookmark : Icons.bookmark_border),
            color: _isCourseSaved ? cs.primary : cs.onSurfaceVariant,
            tooltip: _isCourseSaved ? l10n.courseUnsave : l10n.courseSave,
            onPressed: _toggleCourseSave,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: l10n.unenrollButton,
            onSelected: (v) { if (v == 'unenroll') _confirmUnenroll(); },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'unenroll',
                child: Row(children: [
                  Icon(Icons.exit_to_app, color: cs.error),
                  SizedBox(width: AppSpacing.sm.w),
                  Text(l10n.unenrollButton),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_isDownloaded) _buildDownloadBanner(cs, tt, l10n),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
                child: _loadingResources && _resources.isEmpty
                  ? Center(child: CircularProgressIndicator(color: cs.primary))
                  : _loadFailedResources && _resources.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.cloud_off_rounded, color: cs.error, size: 48.sp),
                              SizedBox(height: AppSpacing.md.h),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w),
                                child: Text(l10n.errorNoServerNoCache,
                                    textAlign: TextAlign.center,
                                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                              ),
                              SizedBox(height: AppSpacing.lg.h),
                              FilledButton.tonal(
                                onPressed: () {
                                  setState(() {
                                    _loadingResources = true;
                                    _loadFailedResources = false;
                                  });
                                  _loadResources();
                                },
                                child: Text(l10n.errorRetryButton),
                              ),
                            ],
                          ),
                        )
                  : _buildGroupedList(cs, tt, l10n),
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

  Widget _buildGroupedList(ColorScheme cs, TextTheme tt, AppLocalizations l10n) {
    final sections = groupResourcesByTopic(_topics, _resources)
        .where((s) => s.resources.isNotEmpty)
        .toList();
    final posById = <String, int>{for (var i = 0; i < _resources.length; i++) _resources[i].id: i};
    final items = <({CourseTopic? topic, CourseResource? resource})>[];
    for (final s in sections) {
      items.add((topic: s.topic, resource: null));
      for (final r in s.resources) {
        items.add((topic: s.topic, resource: r));
      }
    }
    return ListView.builder(
      padding: EdgeInsets.all(AppSpacing.lg.w),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final item = items[i];
        if (item.resource == null) return _buildSectionHeader(item.topic, cs, tt, l10n);
        return Padding(
          padding: EdgeInsets.only(bottom: AppSpacing.md.h),
          child: _buildResourceItem(item.resource!, posById[item.resource!.id] ?? 0, cs, tt, l10n),
        );
      },
    );
  }

  Widget _buildSectionHeader(CourseTopic? topic, ColorScheme cs, TextTheme tt, AppLocalizations l10n) {
    return Padding(
      padding: EdgeInsets.only(top: AppSpacing.md.h, bottom: AppSpacing.sm.h),
      child: Text(
        topic?.title ?? l10n.coursePlayerUngroupedTitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: tt.titleSmall?.copyWith(
          fontWeight: AppSpacing.weightStrong,
          color: cs.onSurface,
        ),
      ),
    );
  }

  Widget _buildResourceItem(CourseResource r, int globalIndex, ColorScheme cs, TextTheme tt, AppLocalizations l10n) {
    final unlocked = _isResourceUnlocked(r);
    final completed = _completed[r.id] == true;
    final isCurrent = globalIndex == _currentPosition && !completed;

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
                  onPressed: () => _openResource(r),
                  child: Text(l10n.coursePlayerStart),
                )
              : Icon(Icons.lock,
                  color: cs.onSurfaceVariant,
                  size: 20.sp,
                  semanticLabel: l10n.coursePlayerLocked),
      // Locked cards stay tappable so the tap can explain the lock.
      onTap: () => _openResource(r),
    );
  }
}
