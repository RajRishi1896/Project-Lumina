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
      return Column(
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
      );
    }

    final total = _session.length;
    return Column(
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
            child: Wrap(
              spacing: AppSpacing.sm.w,
              runSpacing: AppSpacing.sm.w,
              alignment: WrapAlignment.center,
              children: [
                _GradeButton(
                  label: l10n.flashcardAgain,
                  background: cs.error,
                  foreground: cs.onError,
                  onPressed: () => _grade(ReviewGrade.again),
                ),
                _GradeButton(
                  label: l10n.flashcardHard,
                  background: cs.tertiary,
                  foreground: cs.onTertiary,
                  onPressed: () => _grade(ReviewGrade.hard),
                ),
                _GradeButton(
                  label: l10n.flashcardGood,
                  background: cs.primary,
                  foreground: cs.onPrimary,
                  onPressed: () => _grade(ReviewGrade.good),
                ),
                _GradeButton(
                  label: l10n.flashcardEasy,
                  background: cs.secondary,
                  foreground: cs.onSecondary,
                  onPressed: () => _grade(ReviewGrade.easy),
                ),
              ],
            ),
          ),
        Padding(
          padding: EdgeInsets.only(bottom: AppSpacing.lg.h),
          child: Text(
            l10n.flashcardCardProgress(total - _index, total),
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      ],
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.touch_app_outlined, size: AppSpacing.lg.sp, color: cs.onSurfaceVariant),
                    SizedBox(width: AppSpacing.xs.w),
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

/// One of the four self-grading buttons shown after the card is flipped.
class _GradeButton extends StatelessWidget {
  const _GradeButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
      ),
      onPressed: onPressed,
      child: Text(label),
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