import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:edumesh_android/core/constants/app_spacing.dart';
import 'package:edumesh_android/core/models/flashcard_models.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';

/// The flippable study card for [FlashcardStudyPage].
///
/// Front is the dark question face, back the white answer face. The caller
/// drives the reveal through [flipController] (0 = front, 1 = back); the
/// Y-rotation never shows a mirrored face because the visible side switches
/// at the 90-degree point and the angle is folded back afterwards. Callers
/// honoring reduced motion simply jump the controller instead of animating.
class FlashcardFlipCard extends StatelessWidget {
  /// Creates the flip card for [card], labelled with [subject] on the front.
  const FlashcardFlipCard({
    super.key,
    required this.flipController,
    required this.subject,
    required this.card,
    required this.onFlip,
  });

  /// 0..1 reveal animation; >= 0.5 shows the answer side.
  final Animation<double> flipController;

  /// Short label shown above the question (deck subject or title).
  final String subject;

  /// The card whose front/back are rendered.
  final FlashcardCard card;

  /// Called when the student taps the card.
  final VoidCallback onFlip;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AnimatedBuilder(
      animation: flipController,
      builder: (context, _) {
        final t = flipController.value;
        final showBack = t >= 0.5;
        // Fold the angle back after 90 degrees so the back face is never
        // rendered mirrored.
        final angle =
            t <= 0.5 ? t * 3.141592653589793 : (1 - t) * 3.141592653589793;
        final sideLabel = showBack ? l10n.flashcardAnswer : l10n.flashcardFront;
        final sideText = showBack ? card.back : card.front;
        return Semantics(
          button: true,
          label: '$sideLabel: $sideText',
          hint: l10n.flashcardTapReveal,
          onTap: onFlip,
          child: GestureDetector(
            onTap: onFlip,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0015)
                ..rotateY(angle),
              child: _buildFace(context, showBack),
            ),
          ),
        );
      },
    );
  }

  /// Builds the visible face; [showBack] selects the answer side.
  Widget _buildFace(BuildContext context, bool showBack) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppSpacing.xl.w),
      decoration: BoxDecoration(
        color: showBack ? cs.surface : cs.primary,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: showBack ? Border.all(color: cs.outlineVariant) : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!showBack)
            Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.lg.h),
              child: Text(
                subject.toUpperCase(),
                style: tt.labelLarge?.copyWith(color: cs.primaryFixedDim),
              ),
            ),
          if (showBack)
            Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.md.h),
              child: Text(
                l10n.flashcardAnswer,
                style: tt.titleSmall?.copyWith(color: cs.secondary),
              ),
            ),
          Flexible(
            child: SingleChildScrollView(
              child: Text(
                showBack ? card.back : card.front,
                textAlign: TextAlign.center,
                style: (showBack ? tt.bodyLarge : tt.headlineSmall)?.copyWith(
                  color: showBack ? cs.onSurface : cs.onPrimary,
                  fontWeight: AppSpacing.weightStrong,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
