import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:edumesh_android/core/constants/app_spacing.dart';
import 'package:edumesh_android/core/models/flashcard_models.dart';
import 'package:edumesh_android/core/navigation/lumina_transitions.dart';
import 'package:edumesh_android/core/services/flashcard_scheduler.dart';
import 'package:edumesh_android/core/services/flashcard_service.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';

import 'flashcard_flip_card.dart';

/// Runs a review session over the due cards of one flashcard deck.
///
/// Each card is shown front-first and flips on tap with a short Y-rotation
/// (architect-approved exception to the animation ban, scoped to this card).
/// After the reveal the student grades the card with one of the four SM-2
/// buttons, which writes the review state through [FlashcardService].
class FlashcardStudyPage extends StatefulWidget {
  /// The id of the deck whose due cards are reviewed.
  final String deckId;

  /// When true, study all cards in random order (full review).
  /// When false, only study cards that are due today.
  final bool studyAll;

  /// Creates the flashcard study page for [deckId].
  const FlashcardStudyPage({super.key, required this.deckId, this.studyAll = true});

  @override
  State<FlashcardStudyPage> createState() => _FlashcardStudyPageState();
}

class _FlashcardStudyPageState extends State<FlashcardStudyPage>
    with SingleTickerProviderStateMixin {
  FlashcardDeck? _deck;
  List<FlashcardCard> _session = const [];
  int _index = 0;
  bool _loading = true;

  /// Logical reveal state; tracked separately from the controller value so
  /// taps during a mid-flight animation still toggle to the opposite side.
  bool _flipped = false;

  /// Architect-approved flip animation, scoped to the study card:
  /// 160 ms Y-rotation, easeOut, center-aligned, conservative perspective.
  late final AnimationController _flipController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
    value: 0,
  );

  bool get _finished => !_loading && (_session.isEmpty || _index >= _session.length);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final deck = await FlashcardService().getDeck(widget.deckId);
    if (!mounted) return;
    if (deck == null) {
      Navigator.pop(context);
      return;
    }
    final cards = widget.studyAll
        ? (deck.cards.toList()..shuffle(Random()))
        : deck.cards.where((c) => c.isDue).toList();
    setState(() {
      _deck = deck;
      _session = cards;
      _loading = false;
      _index = 0;
      _flipped = false;
    });
    _flipController.value = 0;
  }

  void _flip() {
    // The global setting plus reduced motion both force an instant swap;
    // otherwise run the approved 160 ms flip.
    final animate = LuminaTransitions.enabled(context);
    _flipped = !_flipped;
    final target = _flipped ? 1.0 : 0.0;
    if (!animate) {
      _flipController.value = target;
    } else {
      _flipController.animateTo(target, curve: Curves.easeOut);
    }
  }

  Future<void> _grade(ReviewGrade grade) async {
    final card = _session[_index];
    await FlashcardService().reviewCard(card.id, grade);
    if (!mounted) return;
    setState(() {
      _index += 1;
      _flipped = false;
    });
    _flipController.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    final deck = _deck;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        title: Text(
          deck != null ? l10n.flashcardStudyingDeck(deck.title) : '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tt.titleMedium?.copyWith(color: cs.onSurface),
        ),
      ),
      body: _buildBody(cs, tt, l10n),
    );
  }

  Widget _buildBody(ColorScheme cs, TextTheme tt, AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final deck = _deck!;
    if (deck.cards.isEmpty) {
      return _EmptyNote(
        icon: Icons.style_outlined,
        message: l10n.flashcardNoCards,
        cs: cs,
        tt: tt,
      );
    }
    if (_finished) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_outline, size: 72.sp, color: cs.primary),
              SizedBox(height: AppSpacing.md.h),
              Text(l10n.flashcardSessionComplete, style: tt.titleMedium),
              SizedBox(height: AppSpacing.xl.h),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.buttonContinue),
              ),
            ],
          ),
        ),
      );
    }

    final total = _session.length;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg.w, AppSpacing.lg.h, AppSpacing.lg.w, 0),
                child: Row(
                  children: [
                    Text(
                      l10n.flashcardFocusMode,
                      style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const Spacer(),
                    Text(
                      l10n.flashcardCardProgress(_index + 1, total),
                      style: tt.labelSmall?.copyWith(
                        color: cs.primary,
                        fontWeight: AppSpacing.weightStrong,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg.w, AppSpacing.sm.h, AppSpacing.lg.w, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  child: LinearProgressIndicator(
                    value: (_index + (_flipped ? 0.5 : 0.0)) / total,
                    minHeight: 8.h,
                    backgroundColor: cs.primaryContainer,
                    valueColor: AlwaysStoppedAnimation(cs.tertiary),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg.w, vertical: AppSpacing.md.h),
                  child: FlashcardFlipCard(
                    flipController: _flipController,
                    subject: deck.subject.isEmpty ? deck.title : deck.subject,
                    card: _session[_index],
                    onFlip: _flip,
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: _flipController,
                builder: (context, _) {
                  final showBack = _flipController.value >= 0.5;
                  final animate = LuminaTransitions.enabled(context);
                  return AnimatedSwitcher(
                    duration: animate
                        ? const Duration(milliseconds: 150)
                        : Duration.zero,
                    child: Padding(
                      key: ValueKey(showBack),
                      padding: EdgeInsets.only(bottom: AppSpacing.lg.h),
                      child: showBack
                          ? _SrsControls(
                              card: _session[_index], onGrade: _grade)
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.touch_app_outlined,
                                    size: AppSpacing.lg.sp,
                                    color: cs.onSurfaceVariant),
                                SizedBox(width: AppSpacing.xs.w),
                                Text(
                                  l10n.flashcardTapReveal,
                                  style: tt.bodySmall
                                      ?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The four SM-2 self-grading buttons shown after the reveal, each with the
/// concrete next interval computed by [scheduleNext].
class _SrsControls extends StatelessWidget {
  const _SrsControls({required this.card, required this.onGrade});

  final FlashcardCard card;
  final ValueChanged<ReviewGrade> onGrade;

  int _nextDays(ReviewGrade grade) =>
      scheduleNext(grade, card.ease, card.intervalDays,
              DateTime.now().millisecondsSinceEpoch)
          .intervalDays;

  String _label(ReviewGrade grade, AppLocalizations l10n) {
    switch (grade) {
      case ReviewGrade.again:
        return l10n.flashcardAgain;
      case ReviewGrade.hard:
        return l10n.flashcardHard;
      case ReviewGrade.good:
        return l10n.flashcardGood;
      case ReviewGrade.easy:
        return l10n.flashcardEasy;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    const grades = ReviewGrade.values;
    return Row(
      children: [
        for (var i = 0; i < grades.length; i++) ...[
          if (i > 0) SizedBox(width: AppSpacing.xs.w),
          Expanded(
            child: InkWell(
              onTap: () => onGrade(grades[i]),
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              child: Container(
                constraints:
                    BoxConstraints(minHeight: AppSpacing.touchTarget.h),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  border: Border.all(color: cs.outline),
                ),
                padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs.w, vertical: AppSpacing.xs.h),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _label(grades[i], l10n),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurface,
                        fontWeight: AppSpacing.weightStrong,
                      ),
                    ),
                    SizedBox(height: AppSpacing.xs.h),
                    Text(
                      l10n.flashcardNextInDays(_nextDays(grades[i])),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A centred empty-state note used when a deck has no cards.
class _EmptyNote extends StatelessWidget {
  const _EmptyNote({
    required this.icon,
    required this.message,
    required this.cs,
    required this.tt,
  });

  final IconData icon;
  final String message;
  final ColorScheme cs;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64.sp, color: cs.onSurfaceVariant),
          SizedBox(height: AppSpacing.md.h),
          Text(message, style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}
