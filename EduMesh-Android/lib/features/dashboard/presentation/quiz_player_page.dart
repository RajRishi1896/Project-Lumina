import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:edumesh_android/core/models/course.dart';
import 'package:edumesh_android/core/services/course_service.dart';
import 'package:edumesh_android/core/constants/app_spacing.dart';
import 'package:edumesh_android/shared/widgets/mini_player_controller.dart';
import 'package:edumesh_android/core/network/api_client.dart';
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

  /// Called when the student passes (score >= passThreshold).
  final VoidCallback? onComplete;

  /// Called when the student fails the quiz.
  final VoidCallback? onFail;

  const QuizPlayerPage({
    super.key,
    required this.course,
    required this.resource,
    this.onComplete,
    this.onFail,
  });

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
  bool _loading = true;
  String? _error;
  final Map<int, bool> _correctAnswers = {};
  late final String _startedAt;
  int _totalTimeSeconds = 0;
  late final AppLifecycleListener _lifecycleListener;
  final TextEditingController _fillController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _enableSecure();
    _startedAt = DateTime.now().toIso8601String();
    MiniPlayerController().setQuizActive(true);
    _lifecycleListener = AppLifecycleListener(
      onPause: _onAppBackgrounded,
      onInactive: _onAppBackgrounded,
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

  Future<void> _loadQuiz() async {
    try {
      final resp = await ApiClient.get(
        '/api/courses/${widget.course.id}/resources/${widget.resource.id}/quiz',
      );
      if (resp.statusCode == 200 && resp.data is Map) {
        final quiz = Quiz.fromJson(resp.data as Map<String, dynamic>);
        final questions = List<QuizQuestion>.from(quiz.questions);
        if (quiz.shuffleQuestions) questions.shuffle(Random());
        setState(() {
          _quiz = quiz;
          _questions = questions;
          _totalTimeSeconds = quiz.timeLimitMinutes * 60;
          _loading = false;
        });
        _startTimer();
      } else {
        setState(() {
          _error = 'Failed to load quiz';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
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

  void _submitQuiz({bool autoSubmit = false}) {
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

    final attempt = <String, dynamic>{
      'attempt_id': attemptId,
      'student_id': '',
      'course_id': widget.course.id,
      'resource_id': widget.resource.id,
      'attempt_number': 1,
      'score': _score,
      'passed': _passed,
      'answers_json': jsonEncode({'answers': answersJson}),
      'started_at': _startedAt,
      'submitted_at': DateTime.now().toIso8601String(),
      'time_taken_seconds': _totalTimeSeconds - _secondsRemaining,
      'quiz_version': _quiz?.quizVersion ?? 1,
      'threshold_at_submission': _quiz?.passThreshold ?? 0.0,
    };

    CourseService().submitQuiz(widget.course.id, widget.resource.id, attempt);

    if (_passed && widget.onComplete != null) {
      widget.onComplete!();
    } else if (!_passed && widget.onFail != null) {
      widget.onFail!();
    }

    if (mounted) setState(() {});
  }

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
                Text(_error!, style: tt.bodyLarge),
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
      return const Scaffold(
        body: Center(
          child: Text('Quiz not available'),
        ),
      );
    }

    if (_showResults) return _buildResultsScreen(cs, tt);
    return _buildQuizScreen(cs, tt);
  }

  Widget _buildQuizScreen(ColorScheme cs, TextTheme tt) {
    final answeredCount = _questions.length -
        _questions
            .where((q) {
              final i = _questions.indexOf(q);
              if (q.type == QuizQuestionType.multiSelect) {
                return (_multiAnswers[i] ?? []).isEmpty;
              }
              return (_answers[i] ?? '').isEmpty;
            })
            .length;

    return Scaffold(
      body: PopScope(
        canPop: false,
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(cs, tt, answeredCount),
              Expanded(
                child: _buildQuestionCard(
                    _questions[_currentIndex], cs, tt),
              ),
              _buildBottomNav(cs, tt),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(ColorScheme cs, TextTheme tt, int answeredCount) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.lg.w,
        vertical: AppSpacing.sm.h,
      ),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _quiz!.title,
                  style: tt.titleSmall?.copyWith(
                    fontWeight: AppSpacing.weightStrong,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: AppSpacing.xs.h),
                Text(
                  'Question ${_currentIndex + 1} of ${_questions.length}',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (_quiz!.timeLimitMinutes > 0)
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.sm.w,
                vertical: AppSpacing.xs.h,
              ),
              decoration: BoxDecoration(
                color: _secondsRemaining <= 60
                    ? cs.errorContainer
                    : cs.primaryContainer,
                borderRadius:
                    BorderRadius.circular(AppSpacing.radiusSm.r),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _secondsRemaining <= 60
                        ? Icons.timer_off
                        : Icons.timer,
                    size: 16.sp,
                    color: _secondsRemaining <= 60
                        ? cs.onErrorContainer
                        : cs.onPrimaryContainer,
                  ),
                  SizedBox(width: AppSpacing.xs.w),
                  Text(
                    _formatTime(_secondsRemaining),
                    style: tt.bodySmall?.copyWith(
                      fontWeight: AppSpacing.weightStrong,
                      color: _secondsRemaining <= 60
                          ? cs.onErrorContainer
                          : cs.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(QuizQuestion q, ColorScheme cs, TextTheme tt) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(AppSpacing.lg.w),
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildQuestionTypeBadge(q.type, cs, tt),
              SizedBox(height: AppSpacing.md.h),
              if (q.image != null) ...[
                ClipRRect(
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusMd.r),
                  child: Image.network(
                    q.image!,
                    height: 160.h,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
                SizedBox(height: AppSpacing.md.h),
              ],
              Text(
                q.question,
                style: tt.bodyLarge?.copyWith(
                  fontWeight: AppSpacing.weightStrong,
                ),
              ),
              SizedBox(height: AppSpacing.lg.h),
              ..._buildOptions(q, cs, tt),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionTypeBadge(
      QuizQuestionType type, ColorScheme cs, TextTheme tt) {
    String label;
    IconData icon;
    switch (type) {
      case QuizQuestionType.mcq:
        label = 'Multiple Choice';
        icon = Icons.radio_button_checked;
      case QuizQuestionType.trueFalse:
        label = 'True / False';
        icon = Icons.toggle_on;
      case QuizQuestionType.fillBlanks:
        label = 'Fill in the Blanks';
        icon = Icons.edit_note;
      case QuizQuestionType.multiSelect:
        label = 'Multi-Select';
        icon = Icons.check_box;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.sm.w,
        vertical: AppSpacing.xs.h,
      ),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14.sp, color: cs.onSecondaryContainer),
          SizedBox(width: AppSpacing.xs.w),
          Text(
            label,
            style: tt.labelSmall?.copyWith(
              color: cs.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildOptions(QuizQuestion q, ColorScheme cs, TextTheme tt) {
    switch (q.type) {
      case QuizQuestionType.mcq:
        return [
          RadioGroup<String>(
            groupValue: _answers[_currentIndex],
            onChanged: (v) =>
                setState(() => _answers[_currentIndex] = v),
            child: Column(
              children: q.options.map((opt) {
                final selected = _answers[_currentIndex] == opt;
                return Padding(
                  padding: EdgeInsets.only(bottom: AppSpacing.sm.h),
                  child: RadioListTile<String>(
                    title: Text(opt),
                    value: opt,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm.w),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusMd.r),
                      side: BorderSide(
                        color: selected ? cs.primary : cs.outlineVariant,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ];

      case QuizQuestionType.trueFalse:
        return [
          RadioGroup<String>(
            groupValue: _answers[_currentIndex],
            onChanged: (v) =>
                setState(() => _answers[_currentIndex] = v),
            child: Column(
              children: ['True', 'False'].map((opt) {
                return Padding(
                  padding: EdgeInsets.only(bottom: AppSpacing.sm.h),
                  child: RadioListTile<String>(
                    title: Text(opt),
                    value: opt,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm.w),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd.r),
                      side: BorderSide(color: cs.outlineVariant),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ];

      case QuizQuestionType.fillBlanks:
        return [
          TextField(
            controller: _fillController,
            decoration: InputDecoration(
              hintText: 'Type your answer here...',
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
        return q.options.map((opt) {
          final selected =
              (_multiAnswers[_currentIndex] ?? []).contains(opt);
          return Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.sm.h),
            child: CheckboxListTile(
              title: Text(opt),
              value: selected,
              onChanged: (v) {
                setState(() {
                  _multiAnswers.putIfAbsent(_currentIndex, () => []);
                  if (v == true) {
                    _multiAnswers[_currentIndex]!.add(opt);
                  } else {
                    _multiAnswers[_currentIndex]!.remove(opt);
                  }
                });
              },
              contentPadding:
                  EdgeInsets.symmetric(horizontal: AppSpacing.sm.w),
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(AppSpacing.radiusMd.r),
                side: BorderSide(
                  color: selected ? cs.primary : cs.outlineVariant,
                ),
              ),
            ),
          );
        }).toList();
    }
  }

  Widget _buildBottomNav(ColorScheme cs, TextTheme tt) {
    final isFirst = _currentIndex == 0;
    final isLast = _currentIndex == _questions.length - 1;

    return Container(
      padding: EdgeInsets.all(AppSpacing.md.w),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          if (!isFirst)
            OutlinedButton.icon(
              onPressed: () => _goToQuestion(_currentIndex - 1),
              icon: Icon(Icons.chevron_left, size: 20.sp),
              label: const Text('Previous'),
            )
          else
            const SizedBox.shrink(),
          const Spacer(),
          Text(
            '${_currentIndex + 1} / ${_questions.length}',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const Spacer(),
          if (isLast)
            FilledButton.icon(
              onPressed: _submitted ? null : _submitQuiz,
              icon: Icon(Icons.check, size: 20.sp),
              label: const Text('Submit'),
            )
          else
            FilledButton.icon(
              onPressed: () => _goToQuestion(_currentIndex + 1),
              icon: Icon(Icons.chevron_right, size: 20.sp),
              label: const Text('Next'),
            ),
        ],
      ),
    );
  }

  Widget _buildResultsScreen(ColorScheme cs, TextTheme tt) {
    return Scaffold(
      body: SafeArea(
        child: PopScope(
          canPop: false,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(AppSpacing.lg.w),
                  child: Column(
                    children: [
                      SizedBox(height: AppSpacing.section.h),
                      _buildScoreCircle(cs, tt),
                      SizedBox(height: AppSpacing.lg.h),
                      Text(
                        _passed ? 'Passed!' : 'Failed',
                        style: tt.headlineSmall?.copyWith(
                          fontWeight: AppSpacing.weightDisplay,
                          color: _passed ? cs.primary : cs.error,
                        ),
                      ),
                      SizedBox(height: AppSpacing.sm.h),
                      Text(
                        _passed
                            ? 'Great job! You passed the quiz.'
                            : 'You did not pass. Review the questions below.',
                        style: tt.bodyMedium
                            ?.copyWith(color: cs.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: AppSpacing.section.h),
                      ...List.generate(
                        _questions.length,
                        (i) => _buildResultItem(i, cs, tt),
                      ),
                      SizedBox(height: AppSpacing.section.h),
                    ],
                  ),
                ),
              ),
              _buildResultsBottomBar(cs, tt),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScoreCircle(ColorScheme cs, TextTheme tt) {
    final pct = (_score * 100).round();
    final size = 140.r;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: _score,
              strokeWidth: 10.h,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                _passed ? cs.primary : cs.error,
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$pct%',
                style: tt.displaySmall?.copyWith(
                  fontWeight: AppSpacing.weightDisplay,
                ),
              ),
              Text(
                '${_correctAnswers.values.where((v) => v).length} / ${_questions.length}',
                style: tt.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultItem(int index, ColorScheme cs, TextTheme tt) {
    final q = _questions[index];
    final correct = _correctAnswers[index] ?? false;

    return Padding(
      padding: EdgeInsets.only(bottom: AppSpacing.sm.h),
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.md.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    correct ? Icons.check_circle : Icons.cancel,
                    color: correct ? cs.primary : cs.error,
                    size: 20.sp,
                  ),
                  SizedBox(width: AppSpacing.sm.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Question ${index + 1}',
                          style: tt.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        SizedBox(height: AppSpacing.xs.h),
                        Text(
                          q.question,
                          style: tt.bodyMedium?.copyWith(
                            fontWeight: AppSpacing.weightStrong,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (q.explanation != null && q.explanation!.isNotEmpty) ...[
                SizedBox(height: AppSpacing.sm.h),
                Container(
                  padding: EdgeInsets.all(AppSpacing.sm.w),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusSm.r),
                  ),
                  child: Text(
                    'Explanation: ${q.explanation}',
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultsBottomBar(ColorScheme cs, TextTheme tt) {
    return Container(
      padding: EdgeInsets.all(AppSpacing.md.w),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to Course'),
          ),
        ),
      ),
    );
  }
}
