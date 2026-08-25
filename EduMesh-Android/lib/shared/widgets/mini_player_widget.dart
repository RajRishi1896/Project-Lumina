import 'package:flutter/material.dart';
import 'package:edumesh_android/core/navigation/lumina_transitions.dart';
import 'package:video_player/video_player.dart';
import '../../../core/constants/app_spacing.dart';
import 'mini_player_controller.dart';
import 'video_player_page.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';

/// A floating mini-player overlay shown at the bottom of the screen.
///
/// Displays a small [VideoPlayer] widget with play/pause and close controls.
/// Tapping the player navigates to the full [VideoPlayerPage]. Visibility is
/// driven by [MiniPlayerController.isActive].
class MiniPlayerWidget extends StatelessWidget {
  const MiniPlayerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = MiniPlayerController();
    return ListenableBuilder(
      listenable: Listenable.merge(
        [ctrl, if (ctrl.videoController != null) ctrl.videoController!],
      ),
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        if (ctrl.isQuizActive) return const SizedBox.shrink();
        if (!ctrl.isActive) return const SizedBox.shrink();
        final vc = ctrl.videoController;
        final canShow =
            vc != null && vc.value.isInitialized && !vc.value.hasError;
        final ar = (canShow && vc.value.aspectRatio > 0 && vc.value.aspectRatio.isFinite)
            ? vc.value.aspectRatio
            : 16 / 9;
        return Align(
          alignment: Alignment.bottomCenter,
          child: Semantics(
            button: true,
            label: AppLocalizations.of(context)!.semanticsOpenVideoPlayer,
            child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                luminaRoute(
                  builder: (_) => VideoPlayerPage(
                    title: ctrl.title,
                    videoUrl: ctrl.videoUrl,
                    subject: ctrl.subject,
                    existingController: ctrl.videoController,
                  ),
                ),
              );
            },
            child: Container(
              height: AppSpacing.miniPlayerHeight,
              margin: const EdgeInsets.only(bottom: AppSpacing.pageMargin),
              width: AppSpacing.miniPlayerWidth,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                boxShadow: [
                  BoxShadow(
                    color: cs.scrim.withValues(alpha: 0.12),
                    blurRadius: AppSpacing.radiusMd,
                    offset: const Offset(0, AppSpacing.hairline),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  if (canShow)
                    AspectRatio(
                      aspectRatio: ar,
                      child: VideoPlayer(vc),
                    )
                  else
                    Center(child: Icon(Icons.play_circle_fill, color: cs.onSurfaceVariant, size: 32)),
                  Positioned(
                    right: AppSpacing.xs,
                    top: AppSpacing.xs,
                    child: Semantics(
                      button: true,
                      label: AppLocalizations.of(context)!.semanticsCloseMiniPlayer,
                      child: SizedBox(
                        width: AppSpacing.touchTarget,
                        height: AppSpacing.touchTarget,
                        child: GestureDetector(
                          onTap: () => ctrl.stop(),
                          child: Container(
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: cs.scrim.withValues(alpha: 0.12),
                                  blurRadius: AppSpacing.radiusMd,
                                  offset: const Offset(0, AppSpacing.hairline),
                                ),
                              ],
                            ),
                            child: Icon(Icons.close, color: cs.onSurface, size: 20),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: AppSpacing.xs,
                    bottom: AppSpacing.xs,
                    child: Semantics(
                      button: true,
                      label: AppLocalizations.of(context)!.semanticsTogglePlay,
                      child: SizedBox(
                        width: AppSpacing.touchTarget,
                        height: AppSpacing.touchTarget,
                        child: GestureDetector(
                      onTap: () {
                        if (ctrl.videoController != null) {
                          if (ctrl.videoController!.value.isPlaying) {
                            ctrl.videoController!.pause();
                          } else {
                            ctrl.videoController!.play();
                          }
                        }
                      },
                      child: Container(
                        color: cs.scrim.withValues(alpha: 0.12),
                        padding: const EdgeInsets.all(AppSpacing.xs),
                        child: Icon(
                          ctrl.videoController != null && ctrl.videoController!.value.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                          color: cs.onSurface,
                          size: 18,
                        ),
                      ),
                    ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        );
      },
    );
  }
}
