import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:edumesh_android/core/constants/app_spacing.dart';
import 'package:edumesh_android/core/models/flashcard_models.dart';
import 'package:edumesh_android/core/services/flashcard_scheduler.dart';
import 'package:edumesh_android/core/services/flashcard_service.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';

/// Runs a review session over the due cards of one flashcard deck.
///
/// Each card is shown front-first and flips on tap; the student then grades
/// it with one of the four self-assessment buttons, which writes the SM-2
/// review state through [FlashcardService].
class FlashcardStudyPage extends StatefulWidget {
  /// The id of the deck whose due cards are reviewed.
  final String deckId;

  /// Creates the flashcard study page for [deckId].
  const FlashcardStudyPage({super.key, required this.deckId});

  @override
  State<FlashcardStudyPage> createState() => _FlashcardStudyPageState();
}

class _FlashcardStudyPageState extends State<FlashcardStudyPage> {
  FlashcardDeck? _deck;
  List<FlashcardCard> _session = const [];
  int _index = 0;
  bool _flipped = false;
  bool _loading = true;

  bool get _finished => !_loading && (_session.isEmpty || _index >= _session.length);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final deck = await FlashcardService().getDeck(widget.deckId);
    if (!mounted) return;
    if (deck == null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _deck = deck;
      _session = deck.cards.where((c) => c.isDue).toList();
      _loading = false;
      _index = 0;
      _flipped = false;
    });
  }

  Future<void> _grade(ReviewGrade grade) async {
    final card = _session[_index];
    await FlashcardService().reviewCard(card.id, grade);
    if (!mounted) return;
    setState(() {
      _flipped = false;
      _index += 1;
    });
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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(AppSpacing.lg.w, AppSpacing.lg.h, AppSpacing.lg.w, 0),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              l10n.flashcardCardProgress(_index + 1, total),
              style: tt.titleMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: AppSpacing.weightStrong,
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w, vertical: AppSpacing.sm.h),
            child: _CardFace(
              card: _session[_index],
              flipped: _flipped,
              onTap: () => setState(() => _flipped = !_flipped),
            ),
          ),
        ),
        if (_flipped)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w, vertical: AppSpacing.sm.h),
            child: _GradeOptions(card: _session[_index], onGrade: _grade),
          ),
        Padding(
          padding: EdgeInsets.only(bottom: AppSpacing.lg.h),
          child: Text(
            l10n.flashcardCardProgress(total - _index, total),
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      ],
        ),
      ),
    );
  }
}

/// The flippable card face; front before flip, back plus hint after.
class _CardFace extends StatelessWidget {
  const _CardFace({
    required this.card,
    required this.flipped,
    required this.onTap,
  });

  final FlashcardCard card;
  final bool flipped;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(AppSpacing.xl.w),
        decoration: BoxDecoration(
          color: flipped ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!flipped)
              Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.md.h),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.xs.w,
                  children: [
                    Icon(Icons.touch_app_outlined, size: AppSpacing.lg.sp, color: cs.onSurfaceVariant),
                    Text(
                      l10n.flashcardFlipHint,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            Flexible(
              child: SingleChildScrollView(
                child: Text(
                  flipped ? card.back : card.front,
                  textAlign: TextAlign.center,
                  style: tt.titleMedium?.copyWith(
                    color: flipped ? cs.onPrimaryContainer : cs.onSurface,
                    fontWeight: AppSpacing.weightStrong,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The four self-grading options shown after the card is flipped, laid out
/// as a 2x2 grid (Again | Hard over Good | Easy).
///
/// Each option pairs the grade label with a plain-language description and
/// the concrete next interval computed by [scheduleNext] for the current
/// card, so students see what each choice does before tapping.
class _GradeOptions extends StatelessWidget {
  const _GradeOptions({required this.card, required this.onGrade});

  final FlashcardCard card;
  final ValueChanged<ReviewGrade> onGrade;

  int _nextDays(ReviewGrade grade) {
    final next = scheduleNext(
      grade,
      card.ease,
      card.intervalDays,
      DateTime.now().millisecondsSinceEpoch,
    );
    return next.intervalDays;
  }

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

  String _description(ReviewGrade grade, AppLocalizations l10n) {
    switch (grade) {
      case ReviewGrade.again:
        return l10n.flashcardAgainDesc;
      case ReviewGrade.hard:
        return l10n.flashcardHardDesc;
      case ReviewGrade.good:
        return l10n.flashcardGoodDesc;
      case ReviewGrade.easy:
        return l10n.flashcardEasyDesc;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _option(
                context, ReviewGrade.again, cs.error, cs.onError, cs, l10n,
              ),
            ),
            SizedBox(width: AppSpacing.sm.w),
            Expanded(
              child: _option(
                context, ReviewGrade.hard, cs.tertiary, cs.onTertiary, cs, l10n,
              ),
            ),
          ],
        ),
        SizedBox(height: AppSpacing.sm.h),
        Row(
          children: [
            Expanded(
              child: _option(
                context, ReviewGrade.good, cs.primary, cs.onPrimary, cs, l10n,
              ),
            ),
            SizedBox(width: AppSpacing.sm.w),
            Expanded(
              child: _option(
                context, ReviewGrade.easy, cs.secondary, cs.onSecondary, cs, l10n,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _option(
    BuildContext context,
    ReviewGrade grade,
    Color background,
    Color foreground,
    ColorScheme cs,
    AppLocalizations l10n,
  ) {
    final tt = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => onGrade(grade),
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: AppSpacing.touchTarget.h),
        child: Container(
          padding: EdgeInsets.all(AppSpacing.md.w),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm.w,
                  vertical: AppSpacing.xs.h,
                ),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                ),
                child: Text(
                  _label(grade, l10n),
                  style: tt.labelMedium?.copyWith(
                    color: foreground,
                    fontWeight: AppSpacing.weightStrong,
                  ),
                ),
              ),
              SizedBox(height: AppSpacing.xs.h),
              Text(
                _description(grade, l10n),
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              SizedBox(height: AppSpacing.xs.h),
              Text(
                l10n.flashcardNextInDays(_nextDays(grade)),
                style: tt.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: AppSpacing.weightStrong,
                ),
              ),
            ],
          ),
        ),
      ),
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