import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:edumesh_android/core/models/course.dart';
import 'package:edumesh_android/core/models/resource_model.dart';
import 'package:edumesh_android/core/services/course_service.dart';
import 'package:edumesh_android/core/services/mutation_queue.dart';
import 'package:edumesh_android/core/constants/app_spacing.dart';
import 'package:edumesh_android/features/auth/data/auth_service.dart';
import 'package:edumesh_android/shared/widgets/mini_player_controller.dart';
import 'package:edumesh_android/core/network/api_client.dart';
import 'package:edumesh_android/core/storage/db_helper.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';

/// A full-screen locked-down quiz player with 4 question types
/// (MCQ, True/False, Fill-in-the-Blanks, Multi-Select).
///
/// Enforces time limits, prevents back navigation, auto-submits on
/// app background, and auto-grades on submission.
class QuizPlayerPage extends StatefulWidget {
  /// The course this quiz belongs to.
  final Course course;

  /// The resource metadata for this quiz.
  final CourseResource resource;

  /// The standalone resource model (for non-course quizzes).
  final ResourceModel? resourceModel;

  /// Pre-loaded quiz data (offline path).
  final Map<String, dynamic>? quizData;

  /// Called when the student passes (score >= passThreshold).
  final VoidCallback? onComplete;

  /// Called when the student fails the quiz.
  final VoidCallback? onFail;

  const QuizPlayerPage({
    super.key,
    required this.course,
    required this.resource,
    this.resourceModel,
    this.quizData,
    this.onComplete,
    this.onFail,
  });

  /// Creates a [QuizPlayerPage] for a standalone [ResourceModel] quiz.
  /// If [quizData] is provided (e.g. from a local file), the API fetch is skipped.
  factory QuizPlayerPage.fromResource(ResourceModel resource, {Map<String, dynamic>? quizData}) {
    return QuizPlayerPage(
      course: Course(
        id: resource.id,
        title: resource.title,
        subject: resource.subject,
        grade: int.tryParse(resource.grade) ?? 0,
        language: 'en',
        published: 1,
      ),
      resource: CourseResource(
        id: resource.id,
        courseId: resource.id,
        resourceType: CourseType.quiz,
        title: resource.title,
        fileSize: 0,
        position: 0,
      ),
      resourceModel: resource,
      quizData: quizData,
    );
  }

  @override
  State<QuizPlayerPage> createState() => _QuizPlayerPageState();
}

class _QuizPlayerPageState extends State<QuizPlayerPage> {
  Quiz? _quiz;
  List<QuizQuestion> _questions = [];
  final Map<int, String?> _answers = {};
  final Map<int, List<String>> _multiAnswers = {};
  int _currentIndex = 0;
  int _secondsRemaining = 0;
  Timer? _timer;
  bool _submitted = false;
  bool _passed = false;
  double _score = 0.0;
  bool _showResults = false;
  bool _pendingResults = false;
  bool _loading = true;
  String? _error;
  final Map<int, bool> _correctAnswers = {};
  // Selection identity is the tapped option INDEX, not its text: two options
  // with identical text must stay independently selectable.
  final Map<int, int> _selectedOption = {};
  final Map<int, Set<int>> _multiSelected = {};
  late final String _startedAt;
  int _totalTimeSeconds = 0;
  late final AppLifecycleListener _lifecycleListener;
  final TextEditingController _fillController = TextEditingController();
  double _bestScore = 0.0;
  int _totalAttempts = 0;

  bool get _isStandalone => widget.resourceModel != null;

  @override
  void initState() {
    super.initState();
    _enableSecure();
    _startedAt = DateTime.now().toIso8601String();
    MiniPlayerController().setQuizActive(true);
    _lifecycleListener = AppLifecycleListener(
      onPause: _onAppBackgrounded,
      onDetach: _onAppBackgrounded,
    );
    _loadQuiz();
  }

  void _enableSecure() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  void _onAppBackgrounded() {
    if (!_submitted) _submitQuiz(autoSubmit: true);
  }

  String get _quizUrl => _isStandalone
      ? '/api/quiz-resource/${widget.resourceModel!.id}'
      : '/api/courses/${widget.course.id}/quiz/${widget.resource.id}';

  void _applyShuffle(Quiz quiz, List<QuizQuestion> questions) {
    final mode = quiz.shuffleMode;
    if (mode == 'questions' || mode == 'both') {
      questions.shuffle(Random());
    }
    if (mode == 'options' || mode == 'both') {
      for (final q in questions) {
        if (q.type == QuizQuestionType.mcq || q.type == QuizQuestionType.multiSelect) {
          q.options.shuffle(Random());
        }
      }
    }
  }

  Future<void> _loadQuiz() async {
    if (widget.quizData != null) {
      final quiz = Quiz.fromJson(widget.quizData!);
      final questions = List<QuizQuestion>.from(quiz.questions);
      _applyShuffle(quiz, questions);
      setState(() {
        _quiz = quiz;
        _questions = questions;
        _totalTimeSeconds = quiz.timeLimitMinutes * 60;
        _loading = false;
      });
      _startTimer();
      _fetchBestAttempt();
      return;
    }

    final cacheKey = '${widget.course.id}_${widget.resource.id}';
    try {
      final resp = await ApiClient.get(_quizUrl);
      if (resp.statusCode == 200 && resp.data is Map) {
        final quizData = resp.data as Map<String, dynamic>;
        final quiz = Quiz.fromJson(quizData);
        await DBHelper().cacheQuiz(cacheKey, quizData);
        final questions = List<QuizQuestion>.from(quiz.questions);
        _applyShuffle(quiz, questions);
        if (!mounted) return;
        setState(() {
          _quiz = quiz;
          _questions = questions;
          _totalTimeSeconds = quiz.timeLimitMinutes * 60;
          _loading = false;
        });
        _startTimer();
        _fetchBestAttempt();
        return;
      }
    } catch (_) {}

    final cached = await DBHelper().getCachedQuiz(cacheKey);
    if (cached != null) {
      final quiz = Quiz.fromJson(cached);
      final questions = List<QuizQuestion>.from(quiz.questions);
      _applyShuffle(quiz, questions);
      if (!mounted) return;
      setState(() {
        _quiz = quiz;
        _questions = questions;
        _totalTimeSeconds = quiz.timeLimitMinutes * 60;
        _loading = false;
      });
      _startTimer();
      _fetchBestAttempt();
      return;
    }

    if (!mounted) return;
    setState(() {
      _error = 'load_failed';
      _loading = false;
    });
  }

  void _startTimer() {
    if (_quiz == null || _quiz!.timeLimitMinutes <= 0) return;
    _secondsRemaining = _totalTimeSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _secondsRemaining--);
      if (_secondsRemaining <= 0) {
        t.cancel();
        _submitQuiz(autoSubmit: true);
      }
    });
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _fetchBestAttempt() async {
    try {
      final url = _isStandalone
          ? '/api/quiz-resource/${widget.resourceModel!.id}/best-score'
          : '/student/quiz-best-score/${widget.course.id}/${widget.resource.id}';
      final resp = await ApiClient.get(url);
      if (resp.statusCode == 200 && resp.data is Map) {
        final data = resp.data as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _bestScore = (data['best_score'] as num?)?.toDouble() ?? 0.0;
            _totalAttempts = (data['attempts_count'] as num?)?.toInt() ?? 0;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _submitQuiz({bool autoSubmit = false}) async {
    if (_submitted) return;
    _timer?.cancel();
    _submitted = true;
    _showResults = true;

    int correct = 0;
    for (int i = 0; i < _questions.length; i++) {
      final q = _questions[i];
      final isCorrect = _isAnswerCorrect(i, q);
      if (isCorrect) correct++;
      _correctAnswers[i] = isCorrect;
    }

    _score = _questions.isNotEmpty ? correct / _questions.length : 0;
    _passed = _score >= (_quiz?.passThreshold ?? 0.5);

    final answersJson = <String, dynamic>{};
    for (int i = 0; i < _questions.length; i++) {
      answersJson[i.toString()] = {
        'answer': _answers[i],
        if (_multiAnswers[i] != null) 'multi_answers': _multiAnswers[i],
        'correct': _correctAnswers[i],
        'question_id': _questions[i].id,
      };
    }

    final attemptId =
        '${widget.course.id}_${widget.resource.id}_${DateTime.now().millisecondsSinceEpoch}';

    final studentId = (await AuthService().getUniqueUserId()) ?? '';

    final attempt = <String, dynamic>{
      'attempt_id': attemptId,
      'student_id': studentId,
      'course_id': widget.course.id,
      'resource_id': widget.resource.id,
      'attempt_number': _totalAttempts + 1,
      'score': _score,
      'passed': _passed,
      'answers_json': jsonEncode({'answers': answersJson}),
      'started_at': _startedAt,
      'submitted_at': DateTime.now().toIso8601String(),
      'time_taken_seconds': _totalTimeSeconds - _secondsRemaining,
      'quiz_version': _quiz?.quizVersion ?? 1,
      'threshold_at_submission': _quiz?.passThreshold ?? 0.0,
    };

    final dynamic serverResponse;
    if (_isStandalone) {
      serverResponse = await CourseService()
          .submitStandaloneQuiz(widget.resourceModel!.id, attempt);
    } else {
      serverResponse = await CourseService()
          .submitQuiz(widget.course.id, widget.resource.id, attempt);
    }
    final hasServerGrading = _applyServerResults(serverResponse);
    // Offline submission of a stripped quiz: no server verdict and no local
    // answer key, so any locally computed score would be a lie.
    if (!hasServerGrading && _quizLacksAnswerKey()) {
      _pendingResults = true;
    }

    if (!_pendingResults) {
      if (_score > _bestScore) {
        if (_isStandalone) {
          CourseService().updateStandaloneBestScore(widget.resourceModel!.id, _score, attemptId);
          if (mounted) {
            setState(() {
              _bestScore = _score;
              _totalAttempts++;
            });
          }
        } else {
          unawaited(MutationQueue().enqueue(
            '/student/quiz-best-score/${widget.course.id}/${widget.resource.id}',
            method: 'post',
            body: {'score': _score, 'attempt_id': attemptId},
          ));
          if (mounted) {
            setState(() {
              _bestScore = _score;
              _totalAttempts++;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() => _totalAttempts++);
        }
      }

      if (_passed && widget.onComplete != null) {
        widget.onComplete!();
      } else if (!_passed && widget.onFail != null) {
        widget.onFail!();
      }
    }

    if (mounted) setState(() {});
  }

  /// Applies the server's grading to the on-screen results.
  ///
  /// The served quiz carries no answer key (the server strips it), so when
  /// the submission was graded online the response is authoritative: the
  /// per-question [results] entries supply the verdicts, correct answers,
  /// and explanations, which are merged into the question list so the
  /// review screen renders exactly what the server graded.
  ///
  /// Returns whether [response] carried any server grading at all.
  bool _applyServerResults(dynamic response) {
    if (response is! Map) return false;
    final results = response['results'];
    if (results is List && results.isNotEmpty) {
      final byId = <String, Map<String, dynamic>>{};
      for (final entry in results) {
        if (entry is Map) {
          final qid = entry['question_id']?.toString() ?? '';
          if (qid.isNotEmpty) byId[qid] = Map<String, dynamic>.from(entry);
        }
      }
      final rebuilt = List<QuizQuestion>.from(_questions);
      for (int i = 0; i < rebuilt.length; i++) {
        final q = rebuilt[i];
        final entry = byId[q.id];
        if (entry == null) continue;
        _correctAnswers[i] = entry['correct'] == true;
        final rawAnswers = entry['correct_answers'];
        List<String>? correctAnswers = q.correctAnswers;
        String? correctAnswer = q.correctAnswer;
        if (rawAnswers is List && rawAnswers.isNotEmpty) {
          correctAnswers = rawAnswers.map((e) => e.toString()).toList();
          if (correctAnswers.length == 1 &&
              q.type != QuizQuestionType.multiSelect) {
            correctAnswer = correctAnswers.first;
          }
        }
        final rawExplanation = entry['explanation'];
        rebuilt[i] = QuizQuestion(
          id: q.id,
          type: q.type,
          image: q.image,
          question: q.question,
          options: q.options,
          correctAnswer: correctAnswer,
          correctAnswers: correctAnswers,
          explanation: rawExplanation is String && rawExplanation.isNotEmpty
              ? rawExplanation
              : q.explanation,
          exactMatch: q.exactMatch,
        );
      }
      _questions = rebuilt;
    }
    final serverScore = response['score'];
    if (serverScore is num) {
      _score = serverScore.toDouble();
      _passed = response['passed'] == true || response['passed'] == 1;
    }
    return true;
  }

  /// Whether no question in the loaded quiz carries an answer key.
  bool _quizLacksAnswerKey() => _questions.every((q) =>
      (q.correctAnswer == null || q.correctAnswer!.isEmpty) &&
      (q.correctAnswers == null || q.correctAnswers!.isEmpty));

  bool _isAnswerCorrect(int index, QuizQuestion q) {
    switch (q.type) {
      case QuizQuestionType.mcq:
      case QuizQuestionType.trueFalse:
      case QuizQuestionType.fillBlanks:
        final answer = _answers[index];
        if (answer == null || q.correctAnswer == null) return false;
        if (q.exactMatch) {
          return answer.trim().toLowerCase() ==
              q.correctAnswer!.trim().toLowerCase();
        }
        return answer
            .trim()
            .toLowerCase()
            .contains(q.correctAnswer!.trim().toLowerCase());
      case QuizQuestionType.multiSelect:
        final selected = _multiAnswers[index] ?? [];
        final correct = q.correctAnswers ?? [];
        if (selected.length != correct.length) return false;
        return selected.every((s) => correct.contains(s));
    }
  }

  void _goToQuestion(int index) {
    if (index < 0 || index >= _questions.length) return;
    _fillController.text = _answers[index] ?? '';
    setState(() => _currentIndex = index);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycleListener.dispose();
    _fillController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    MiniPlayerController().setQuizActive(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.lg.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48.sp, color: cs.error),
                SizedBox(height: AppSpacing.md.h),
                Text(_error == 'load_failed' ? l10n.quizLoadingError : _error!, style: tt.bodyLarge),
                SizedBox(height: AppSpacing.lg.h),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.buttonCancel),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_quiz == null) {
      return Scaffold(
        body: Center(
          child: Text(l10n.quizNotAvailable),
        ),
      );
    }

    if (_showResults) return _buildResultsScreen(cs, tt, l10n);
    return _buildQuizScreen(cs, tt, l10n);
  }

  Widget _buildQuizScreen(ColorScheme cs, TextTheme tt, AppLocalizations l10n) {
    final q = _questions[_currentIndex];
    final progress = (_currentIndex + 1) / _questions.length;
    final isLast = _currentIndex == _questions.length - 1;
    return Scaffold(
      backgroundColor: cs.surface,
      body: PopScope(
        canPop: false,
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(cs, tt, l10n),
              LinearProgressIndicator(
                value: progress,
                minHeight: AppSpacing.xs.h,
                backgroundColor: cs.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
                    child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg.w,
                    vertical: AppSpacing.xl.h,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_currentIndex + 1}.',
                        style: tt.titleMedium?.copyWith(
                          fontWeight: AppSpacing.weightStrong,
                          color: cs.primary,
                        ),
                      ),
                      SizedBox(height: AppSpacing.sm.h),
                      if (q.image != null) ...[
                        ClipRRect(
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusMd.r),
                          child: Image.network(
                            q.image!,
                            height: 160.h,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                        SizedBox(height: AppSpacing.md.h),
                      ],
                      Text(
                        q.question,
                        style: tt.bodyLarge?.copyWith(
                          fontWeight: AppSpacing.weightStrong,
                          fontSize: 16.sp,
                        ),
                      ),
                      SizedBox(height: AppSpacing.xl.h),
                      ..._buildOptions(q, cs, tt, l10n),
                      if (isLast) ...[
                        SizedBox(height: AppSpacing.xxl.h),
                        SizedBox(
                          width: double.infinity,
                          height: AppSpacing.touchTarget,
                          child: FilledButton(
                            onPressed: _submitted ? null : _submitQuiz,
                            child: Text(
                              l10n.quizSubmit,
                              style: tt.labelLarge?.copyWith(
                                fontWeight: AppSpacing.weightStrong,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  ),
                ),
              ),
              ),
              _buildBottomNav(cs, tt, l10n),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(ColorScheme cs, TextTheme tt, AppLocalizations l10n) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.lg.w,
        vertical: AppSpacing.md.h,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _quiz!.title,
              style: tt.titleSmall?.copyWith(
                fontWeight: AppSpacing.weightStrong,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_quiz!.timeLimitMinutes > 0) ...[
            SizedBox(width: AppSpacing.sm.w),
            Icon(
              _secondsRemaining <= 60 ? Icons.timer_off : Icons.timer,
              size: 16.sp,
              color: _secondsRemaining <= 60
                  ? cs.error
                  : cs.onSurfaceVariant,
            ),
            SizedBox(width: AppSpacing.xs.w),
            Text(
              _formatTime(_secondsRemaining),
              style: tt.bodySmall?.copyWith(
                fontWeight: AppSpacing.weightStrong,
                color: _secondsRemaining <= 60
                    ? cs.error
                    : cs.onSurfaceVariant,
              ),
            ),
          ],
          if (_bestScore > 0) ...[
            SizedBox(width: AppSpacing.md.w),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.sm.w,
                vertical: AppSpacing.xs.h,
              ),
              decoration: BoxDecoration(
                color: cs.tertiaryContainer,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm.r),
              ),
              child: Text(
                'Best: ${(_bestScore * 100).round()}%',
                style: tt.labelSmall?.copyWith(
                  fontWeight: AppSpacing.weightStrong,
                  color: cs.onTertiaryContainer,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Localized display options for [q].
  ///
  /// True/False questions always show the localized [AppLocalizations.quizTrue]
  /// / [AppLocalizations.quizFalse] labels instead of the server's raw English
  /// options; every other question type shows the server-provided options.
  List<String> _displayOptions(QuizQuestion q, AppLocalizations l10n) {
    return q.type == QuizQuestionType.trueFalse
        ? [l10n.quizTrue, l10n.quizFalse]
        : q.options;
  }

  /// Canonical, locale-independent answer value for the True/False option at
  /// [idx].
  ///
  /// The server stores the English 'True'/'False' in
  /// [QuizQuestion.correctAnswer], so the selected answer must be recorded in
  /// that same canonical form for grading to work in every locale. Only the
  /// displayed label is localized.
  String _tfCanonical(int idx) => idx == 0 ? 'True' : 'False';

  /// The canonical value stored in [_answers] for the option at [idx] of [q].
  String _canonicalOption(QuizQuestion q, int idx, AppLocalizations l10n) {
    return q.type == QuizQuestionType.trueFalse
        ? _tfCanonical(idx)
        : _displayOptions(q, l10n)[idx];
  }

  /// Index of the currently selected display option for [q], or null when
  /// nothing is selected.
  ///
  /// The tapped index is tracked explicitly because options with duplicate
  /// text must not collapse the selection onto the first text match.
  int? _selectedDisplayIndex(QuizQuestion q, AppLocalizations l10n) {
    final tracked = _selectedOption[_currentIndex];
    if (tracked != null && tracked < _displayOptions(q, l10n).length) {
      return tracked;
    }
    final answer = _answers[_currentIndex];
    if (answer == null) return null;
    for (int i = 0; i < _displayOptions(q, l10n).length; i++) {
      if (_canonicalOption(q, i, l10n) == answer) return i;
    }
    return null;
  }

  /// Toggles [idx] for the current question and re-derives [_multiAnswers]
  /// from the selected indexes so duplicate option texts stay independently
  /// selectable while the submitted answer remains option text.
  void _toggleMulti(QuizQuestion q, int idx) {
    final set = _multiSelected.putIfAbsent(_currentIndex, () => <int>{});
    if (!set.add(idx)) {
      set.remove(idx);
    }
    final ordered = set.toList()..sort();
    _multiAnswers[_currentIndex] =
        ordered.map((i) => q.options[i]).toList();
  }

  List<Widget> _buildOptions(QuizQuestion q, ColorScheme cs, TextTheme tt, AppLocalizations l10n) {
    switch (q.type) {
      case QuizQuestionType.mcq:
      case QuizQuestionType.trueFalse:
        final options = _displayOptions(q, l10n);
        final selectedIdx = _selectedDisplayIndex(q, l10n);
        return options.asMap().entries.map((entry) {
          final idx = entry.key;
          final opt = entry.value;
          return Column(
            children: [
              InkWell(
                onTap: () => setState(() {
                  _answers[_currentIndex] = _canonicalOption(q, idx, l10n);
                  _selectedOption[_currentIndex] = idx;
                }),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd.r),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: AppSpacing.touchTarget,
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm.w,
                      vertical: AppSpacing.xs.h,
                    ),
                    child: Row(
                      children: [
                        Radio<int>(
                          value: idx,
                          groupValue: selectedIdx,
                          onChanged: (_) => setState(() {
                            _answers[_currentIndex] =
                                _canonicalOption(q, idx, l10n);
                            _selectedOption[_currentIndex] = idx;
                          }),
                          activeColor: cs.primary,
                          visualDensity: VisualDensity.compact,
                        ),
                        SizedBox(width: AppSpacing.sm.w),
                        Expanded(
                          child: Text(
                            opt,
                            style: tt.bodyMedium?.copyWith(
                              fontSize: 14.sp,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (entry.key < options.length - 1)
                Divider(height: 1, color: cs.outlineVariant),
            ],
          );
        }).toList();

      case QuizQuestionType.fillBlanks:
        return [
          TextField(
            controller: _fillController,
            decoration: InputDecoration(
              hintText: l10n.quizFillBlanksHint,
              border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(AppSpacing.radiusMd.r),
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: AppSpacing.md.w,
                vertical: AppSpacing.md.h,
              ),
            ),
            onChanged: (v) {
              _answers[_currentIndex] = v;
            },
            enableInteractiveSelection: false,
            enableSuggestions: false,
          ),
        ];

      case QuizQuestionType.multiSelect:
        return q.options.asMap().entries.map((entry) {
          final idx = entry.key;
          final opt = entry.value;
          final selected =
              (_multiSelected[_currentIndex] ?? const <int>{}).contains(idx);
          return Column(
            children: [
              InkWell(
                onTap: () {
                  setState(() => _toggleMulti(q, idx));
                },
                borderRadius:
                    BorderRadius.circular(AppSpacing.radiusMd.r),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: AppSpacing.touchTarget,
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm.w,
                      vertical: AppSpacing.xs.h,
                    ),
                    child: Row(
                      children: [
                        Checkbox(
                          value: selected,
                          onChanged: (_) {
                            setState(() => _toggleMulti(q, idx));
                          },
                          activeColor: cs.primary,
                          visualDensity: VisualDensity.compact,
                        ),
                        SizedBox(width: AppSpacing.sm.w),
                        Expanded(
                          child: Text(
                            opt,
                            style: tt.bodyMedium?.copyWith(
                              fontSize: 14.sp,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (entry.key < q.options.length - 1)
                Divider(height: 1, color: cs.outlineVariant),
            ],
          );
        }).toList();
    }
  }

  Widget _buildBottomNav(ColorScheme cs, TextTheme tt, AppLocalizations l10n) {
    final isFirst = _currentIndex == 0;
    final isLast = _currentIndex == _questions.length - 1;

    if (isLast) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: EdgeInsets.all(AppSpacing.md.w),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          if (!isFirst)
            OutlinedButton(
              onPressed: () => _goToQuestion(_currentIndex - 1),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, AppSpacing.touchTarget),
              ),
              child: Text(l10n.quizPrevious),
            )
          else
            const SizedBox.shrink(),
          Expanded(
            child: Text(
              l10n.quizQuestionOf(_currentIndex + 1, _questions.length),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          FilledButton(
            onPressed: () => _goToQuestion(_currentIndex + 1),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, AppSpacing.touchTarget),
            ),
            child: Text(l10n.quizNext),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsScreen(ColorScheme cs, TextTheme tt, AppLocalizations l10n) {
    final correctCount = _correctAnswers.values.where((v) => v).length;
    final pct = (_score * 100).round();
    final headerBg = _pendingResults
        ? cs.surfaceContainerHighest
        : (_passed ? cs.primaryContainer : cs.errorContainer);
    final headerFg = _pendingResults
        ? cs.onSurface
        : (_passed ? cs.onPrimaryContainer : cs.onErrorContainer);

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: PopScope(
          canPop: false,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(AppSpacing.lg.w),
                color: headerBg,
                child: Column(
                  children: [
                    Text(
                      _pendingResults
                          ? l10n.quizResultsPendingTitle
                          : (_passed ? l10n.quizPassed : l10n.quizFailed),
                      style: tt.headlineSmall?.copyWith(
                        fontWeight: AppSpacing.weightDisplay,
                        color: headerFg,
                      ),
                    ),
                    if (_pendingResults) ...[
                      SizedBox(height: AppSpacing.sm.h),
                      Text(
                        l10n.quizResultsPendingBody,
                        textAlign: TextAlign.center,
                        style: tt.bodyMedium?.copyWith(color: headerFg),
                      ),
                    ] else ...[
                      SizedBox(height: AppSpacing.sm.h),
                      Text(
                        l10n.quizScoreFraction(correctCount, _questions.length),
                        style: tt.bodyLarge?.copyWith(
                          fontWeight: AppSpacing.weightStrong,
                          color: headerFg,
                        ),
                      ),
                      Text(
                        '$pct%',
                        style: tt.headlineMedium?.copyWith(
                          fontWeight: AppSpacing.weightDisplay,
                          color: headerFg,
                        ),
                      ),
                      if (_totalAttempts > 1) ...[
                        SizedBox(height: AppSpacing.xs.h),
                        Text(
                          'Attempt $_totalAttempts · Best: ${(_bestScore * 100).round()}%',
                          style: tt.bodySmall?.copyWith(
                            color: headerFg,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.all(AppSpacing.lg.w),
                  itemCount: _questions.length,
                  separatorBuilder: (_, __) =>
                      SizedBox(height: AppSpacing.sm.h),
                  itemBuilder: (context, i) =>
                      _buildResultItem(i, cs, tt, l10n),
                ),
              ),
              Container(
                padding: EdgeInsets.all(AppSpacing.md.w),
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border(top: BorderSide(color: cs.outlineVariant)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: AppSpacing.touchTarget,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.quizBackToCourse),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultItem(int index, ColorScheme cs, TextTheme tt, AppLocalizations l10n) {
    final q = _questions[index];
    // Null while results are pending an online flush: no verdict to show.
    final bool? correct =
        _pendingResults ? null : (_correctAnswers[index] ?? false);
    final userAnswer = _answers[index];
    final userMulti = _multiAnswers[index];

    return Container(
      decoration: BoxDecoration(
        color: correct == true
            ? cs.primaryContainer
            : correct == false
                ? cs.errorContainer
                : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd.r),
        border: Border.all(
          color: correct == null
              ? cs.outlineVariant
              : (correct ? cs.primary : cs.error),
          width: 1,
        ),
      ),
      padding: EdgeInsets.all(AppSpacing.md.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                correct == true
                    ? Icons.check_circle
                    : correct == false
                        ? Icons.cancel
                        : Icons.circle_outlined,
                color: correct == null
                    ? cs.onSurfaceVariant
                    : (correct ? cs.primary : cs.error),
                size: 20.sp,
              ),
              SizedBox(width: AppSpacing.sm.w),
              Expanded(
                child: Text(
                  '${index + 1}. ${q.question}',
                  style: tt.bodyMedium?.copyWith(
                    fontWeight: AppSpacing.weightStrong,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.sm.h),
          if (_pendingResults)
            Text(
              userAnswer ?? userMulti?.join(', ') ?? '-',
              style: tt.bodyMedium?.copyWith(color: cs.onSurface),
            )
          else if (q.type == QuizQuestionType.fillBlanks)
            _buildFillBlanksResult(q, userAnswer, cs, tt)
          else if (q.type == QuizQuestionType.multiSelect)
            _buildMultiResult(q, userMulti, cs, tt, index)
          else
            _buildSingleResult(q, userAnswer, cs, tt, l10n, index),
          if (q.explanation != null && q.explanation!.isNotEmpty) ...[
            SizedBox(height: AppSpacing.sm.h),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(AppSpacing.sm.w),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius:
                    BorderRadius.circular(AppSpacing.radiusSm.r),
              ),
              child: Text(
                l10n.quizExplanation(q.explanation ?? ''),
                style: tt.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSingleResult(
      QuizQuestion q, String? userAnswer, ColorScheme cs, TextTheme tt, AppLocalizations l10n, int questionIndex) {
    final options = _displayOptions(q, l10n);
    final correctOpt = (q.correctAnswer ?? '').trim().toLowerCase();
    final selectedIdx = _selectedOption[questionIndex];
    return Column(
      children: options.asMap().entries.map((entry) {
        final canonical = _canonicalOption(q, entry.key, l10n);
        // Case-insensitive, like the grading in [_isAnswerCorrect].
        final isCorrectOption = canonical.trim().toLowerCase() == correctOpt;
        // Duplicate option texts are indistinguishable to the server (it
        // grades by text), so only the actually-tapped index is marked.
        final isUserChoice = selectedIdx != null
            ? entry.key == selectedIdx
            : canonical == userAnswer;
        Color bgColor;
        if (isCorrectOption) {
          bgColor = cs.primaryContainer;
        } else if (isUserChoice && !isCorrectOption) {
          bgColor = cs.errorContainer;
        } else {
          bgColor = Colors.transparent;
        }
        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.sm.w,
            vertical: AppSpacing.xs.h,
          ),
          margin: EdgeInsets.only(bottom: AppSpacing.xs.h),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm.r),
          ),
          child: Row(
            children: [
              Icon(
                isCorrectOption
                    ? Icons.check_circle
                    : (isUserChoice ? Icons.cancel : Icons.circle_outlined),
                size: 16.sp,
                color: isCorrectOption
                    ? cs.primary
                    : (isUserChoice ? cs.error : cs.onSurfaceVariant),
              ),
              SizedBox(width: AppSpacing.sm.w),
              Expanded(
                child: Text(
                  entry.value,
                  style: tt.bodyMedium?.copyWith(
                    fontSize: 14.sp,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMultiResult(
      QuizQuestion q, List<String>? userSelections, ColorScheme cs, TextTheme tt, int questionIndex) {
    final correctSet = Set<String>.from(q.correctAnswers ?? []);
    final selectedIdxs = _multiSelected[questionIndex] ?? const <int>{};
    return Column(
      children: q.options.asMap().entries.map((entry) {
        final opt = entry.value;
        final isCorrectOption = correctSet.contains(opt);
        final isUserChoice = selectedIdxs.contains(entry.key);
        Color bgColor;
        if (isCorrectOption) {
          bgColor = cs.primaryContainer;
        } else if (isUserChoice && !isCorrectOption) {
          bgColor = cs.errorContainer;
        } else {
          bgColor = Colors.transparent;
        }
        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.sm.w,
            vertical: AppSpacing.xs.h,
          ),
          margin: EdgeInsets.only(bottom: AppSpacing.xs.h),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm.r),
          ),
          child: Row(
            children: [
              Icon(
                isCorrectOption
                    ? Icons.check_circle
                    : (isUserChoice ? Icons.cancel : Icons.circle_outlined),
                size: 16.sp,
                color: isCorrectOption
                    ? cs.primary
                    : (isUserChoice ? cs.error : cs.onSurfaceVariant),
              ),
              SizedBox(width: AppSpacing.sm.w),
              Expanded(
                child: Text(
                  opt,
                  style: tt.bodyMedium?.copyWith(
                    fontSize: 14.sp,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFillBlanksResult(
      QuizQuestion q, String? userAnswer, ColorScheme cs, TextTheme tt) {
    final correct = _isAnswerCorrect(
      _questions.indexOf(q),
      q,
    );
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppSpacing.sm.w),
      margin: EdgeInsets.only(bottom: AppSpacing.xs.h),
      decoration: BoxDecoration(
        color: correct ? cs.primaryContainer : cs.errorContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your answer: ${userAnswer ?? '-'}',
            style: tt.bodyMedium?.copyWith(
              fontSize: 14.sp,
              color: cs.onSurface,
            ),
          ),
          if (!correct && q.correctAnswer != null)
            Text(
              'Correct: ${q.correctAnswer}',
              style: tt.bodyMedium?.copyWith(
                fontSize: 14.sp,
                fontWeight: AppSpacing.weightStrong,
                color: cs.primary,
              ),
            ),
        ],
      ),
    );
  }
}
