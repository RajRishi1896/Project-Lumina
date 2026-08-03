import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/services/activity_tracker.dart';
import '../../../core/storage/db_helper.dart';
import '../../../l10n/app_localizations.dart';

/// A parent-facing study report compiled locally from the app's SQLite data.
///
/// Shows study time by subject, downloaded files, quiz best scores, and recent
/// activity. Everything comes from [DBHelper] and [ActivityTracker] so the
/// report works fully offline -- no server round-trips.
class StudyReportPage extends StatefulWidget {
  const StudyReportPage({super.key});

  @override
  State<StudyReportPage> createState() => _StudyReportPageState();
}

class _StudyReportPageState extends State<StudyReportPage> {
  final List<({String subject, int minutes})> _subjectMinutes = [];
  final List<Map<String, dynamic>> _downloads = [];
  final List<({String title, double percent})> _scores = [];
  final List<Map<String, dynamic>> _recent = [];
  bool _loading = true;

  /// Whether any data exists at all -- drives the empty state.
  bool get _hasData =>
      _subjectMinutes.isNotEmpty ||
      _downloads.isNotEmpty ||
      _scores.isNotEmpty ||
      _recent.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = await DBHelper().database;

      final subjectRows = await db.rawQuery(
        'SELECT subject, SUM(seconds) AS total FROM activity '
        'WHERE subject IS NOT NULL AND seconds >= 30 '
        'GROUP BY subject ORDER BY total DESC',
      );
      _subjectMinutes
        ..clear()
        ..addAll(subjectRows.map((r) {
          final name = r['subject']?.toString() ?? '';
          final minutes = (((r['total'] as num?)?.toInt() ?? 0) / 60).round();
          return (subject: name, minutes: minutes);
        }).where((e) => e.subject.isNotEmpty));

      final downloaded = await DBHelper().getDownloadedResources();
      _downloads
        ..clear()
        ..addAll(downloaded);

      final scoreRows = await db.rawQuery(
        'SELECT course_id, resource_id, MAX(score) AS best '
        'FROM quiz_attempts WHERE score > 0 '
        'GROUP BY course_id, resource_id ORDER BY best DESC',
      );
      final titles = await _quizTitleByKey(db);
      _scores
        ..clear()
        ..addAll(scoreRows.map((r) {
          final key = '${r['course_id']}_${r['resource_id']}';
          return (
            title: titles[key] ?? r['resource_id']?.toString() ?? '',
            percent: ((r['best'] as num?)?.toDouble() ?? 0) * 100,
          );
        }).where((e) => e.title.isNotEmpty));

      _recent
        ..clear()
        ..addAll(await ActivityTracker().getActivityHistory(limit: 20));
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  /// Builds a `cache_key -> quiz title` map from the local [quiz_cache] table.
  Future<Map<String, String>> _quizTitleByKey(dynamic db) async {
    final titles = <String, String>{};
    try {
      final cacheRows = await db.query('quiz_cache');
      for (final row in cacheRows) {
        final key = row['cache_key']?.toString() ?? '';
        if (key.isEmpty) continue;
        try {
          final quiz = jsonDecode(row['quiz_json'] as String) as Map<String, dynamic>;
          final title = quiz['title']?.toString() ?? '';
          if (title.isNotEmpty) titles[key] = title;
        } catch (_) {}
      }
    } catch (_) {}
    return titles;
  }

  String _timeLabel(dynamic timestamp, AppLocalizations l10n) {
    if (timestamp == null) return '';
    DateTime dt;
    if (timestamp is DateTime) {
      dt = timestamp;
    } else if (timestamp is int) {
      dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    } else {
      final parsed = DateTime.tryParse(timestamp.toString());
      if (parsed == null) return '';
      dt = parsed;
    }
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return l10n.relativeTimeJustNow;
    if (diff.inMinutes < 60) return l10n.relativeTimeMinutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return l10n.relativeTimeHoursAgo(diff.inHours);
    if (diff.inDays < 30) return l10n.relativeTimeDaysAgo(diff.inDays);
    return l10n.relativeTimeMonthsAgo(diff.inDays ~/ 30);
  }

  String _activityLabel(Map<String, dynamic> activity, AppLocalizations l10n) {
    final action = (activity['action'] as String? ?? '').toLowerCase();
    String verb;
    switch (action) {
      case 'view':
        verb = l10n.activityVerbViewed;
        break;
      case 'search':
        verb = l10n.activityVerbSearched;
        break;
      case 'download':
        verb = l10n.activityVerbDownloaded;
        break;
      case 'watch':
        verb = l10n.activityVerbWatched;
        break;
      case 'save':
        verb = l10n.activityVerbSaved;
        break;
      case 'open':
        verb = l10n.activityVerbOpened;
        break;
      case 'complete':
        verb = l10n.activityVerbCompleted;
        break;
      case 'study_session':
        verb = l10n.activityVerbStudied;
        break;
      case '':
        return '';
      default:
        verb = '';
    }
    final title =
        activity['resource_title']?.toString() ??
        activity['title']?.toString() ??
        '';
    if (title.isNotEmpty) return verb.isEmpty ? title : '$verb $title';
    if (verb.isEmpty) return '';
    return verb;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.studyReportTitle),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_hasData
              ? _buildEmpty(cs)
              : _buildReport(cs),
    );
  }

  Widget _buildEmpty(ColorScheme cs) {
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.xxl.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insights_rounded, size: 56.sp, color: cs.onSurfaceVariant),
            SizedBox(height: AppSpacing.lg.h),
            Text(
              l10n.studyReportEmpty,
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReport(ColorScheme cs) {
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: EdgeInsets.all(AppSpacing.lg.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_subjectMinutes.isNotEmpty) ...[
            _sectionTitle(l10n.studyReportBySubject),
            SizedBox(height: AppSpacing.md.h),
            _card(_buildSubjectList()),
            SizedBox(height: AppSpacing.xxl.h),
          ],
          if (_downloads.isNotEmpty) ...[
            _sectionTitle(l10n.studyReportDownloads),
            SizedBox(height: AppSpacing.xs.h),
            Text(
              '${_downloads.length} ${l10n.studyReportFiles}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            SizedBox(height: AppSpacing.md.h),
            _card(_buildDownloadsList()),
            SizedBox(height: AppSpacing.xxl.h),
          ],
          if (_scores.isNotEmpty) ...[
            _sectionTitle(l10n.studyReportScores),
            SizedBox(height: AppSpacing.md.h),
            _card(_buildScoresList()),
            SizedBox(height: AppSpacing.xxl.h),
          ],
          if (_recent.isNotEmpty) ...[
            _sectionTitle(l10n.studyReportRecent),
            SizedBox(height: AppSpacing.md.h),
            _card(_buildRecentList()),
            SizedBox(height: AppSpacing.xxl.h),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Text(text, style: tt.titleLarge?.copyWith(color: cs.onSurface));
  }

  Widget _card(Widget child) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm.r),
      ),
      child: child,
    );
  }

  Widget _buildSubjectList() {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _subjectMinutes.length,
      itemBuilder: (context, index) {
        final entry = _subjectMinutes[index];
        return ListTile(
          dense: true,
          leading: Icon(Icons.subject_rounded, size: 18.sp, color: cs.primary),
          title: Text(
            entry.subject,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tt.bodySmall?.copyWith(color: cs.onSurface),
          ),
          trailing: Text(
            '${entry.minutes}${l10n.studyReportMin}',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        );
      },
    );
  }

  Widget _buildDownloadsList() {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _downloads.length,
      itemBuilder: (context, index) {
        final row = _downloads[index];
        final title = row['title']?.toString() ?? '';
        if (title.isEmpty) return const SizedBox.shrink();
        return ListTile(
          dense: true,
          leading: Icon(Icons.download_done_rounded, size: 18.sp, color: cs.primary),
          title: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: tt.bodySmall?.copyWith(color: cs.onSurface),
          ),
        );
      },
    );
  }

  Widget _buildScoresList() {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _scores.length,
      itemBuilder: (context, index) {
        final entry = _scores[index];
        return ListTile(
          dense: true,
          leading: Icon(Icons.quiz_rounded, size: 18.sp, color: cs.primary),
          title: Text(
            entry.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: tt.bodySmall?.copyWith(color: cs.onSurface),
          ),
          trailing: Text(
            '${entry.percent.round()}%',
            style: tt.bodySmall?.copyWith(
              fontWeight: AppSpacing.weightStrong,
              color: cs.primary,
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecentList() {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _recent.length,
      itemBuilder: (context, index) {
        final event = _recent[index];
        final label = _activityLabel(event, l10n);
        if (label.isEmpty) return const SizedBox.shrink();
        return ListTile(
          dense: true,
          leading: Icon(Icons.history_rounded, size: 18.sp, color: cs.primary),
          title: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tt.bodySmall?.copyWith(color: cs.onSurface),
          ),
          trailing: Text(
            _timeLabel(event['timestamp'], l10n),
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        );
      },
    );
  }
}