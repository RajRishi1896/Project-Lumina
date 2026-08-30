import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/navigation/lumina_transitions.dart';
import '../../../l10n/app_localizations.dart';
import 'mini_player_controller.dart';
import 'video_player_page.dart';

/// YouTube-style expandable mini-player overlay.
///
/// Two states:
/// - **Collapsed**: compact horizontal bar at the bottom with thumbnail,
///   title, play/pause, close, and thin progress bar.
/// - **Expanded**: larger floating panel with full video, seek bar, and
///   playback controls.
///
/// Supports drag-to-expand/collapse and tap-to-expand. Persisted via
/// [Overlay] so it survives page navigations.
class MiniPlayerWidget extends StatefulWidget {
  const MiniPlayerWidget({super.key});

  static void attach(BuildContext context) {
    final state = context.findAncestorStateOfType<_MiniPlayerOverlayState>();
    state?._attach();
  }

  @override
  State<MiniPlayerWidget> createState() => _MiniPlayerOverlayState();
}

class _MiniPlayerOverlayState extends State<MiniPlayerWidget> {
  OverlayEntry? _entry;
  final _ctrl = MiniPlayerController();

  void _attach() {
    if (_entry != null) return;
    _entry = OverlayEntry(builder: _buildOverlay);
    Overlay.of(context).insert(_entry!);
    _ctrl.setOverlayEntry(_entry);
  }

  @override
  void dispose() {
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildOverlay(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _ctrl,
        if (_ctrl.videoController != null) _ctrl.videoController!,
      ]),
      builder: (context, _) {
        if (_ctrl.isQuizActive || !_ctrl.isActive) {
          return const SizedBox.shrink();
        }
        final vc = _ctrl.videoController;
        bool canShow;
        double ar;
        try {
          canShow =
              vc != null && vc.value.isInitialized && !vc.value.hasError;
          ar = (canShow &&
                  vc.value.aspectRatio > 0 &&
                  vc.value.aspectRatio.isFinite)
              ? vc.value.aspectRatio
              : 16 / 9;
        } catch (_) {
          return const SizedBox.shrink();
        }
        final cs = Theme.of(context).colorScheme;
        final l10n = AppLocalizations.of(context)!;
        final screen = MediaQuery.of(context).size;
        final isTablet = screen.width > 600;
        final animate = LuminaTransitions.enabled(context);
        final animDur =
            animate ? const Duration(milliseconds: 200) : Duration.zero;

        // Responsive dimensions
        final collapsedW = isTablet ? 260.0 : 200.0;
        final collapsedH = isTablet ? 80.0 : 72.0;
        final expandedW =
            isTablet ? screen.width * 0.55 : screen.width * 0.92;
        final expandedH =
            isTablet ? screen.height * 0.50 : screen.height * 0.45;

        final isExpanded = _ctrl.isExpanded;
        final width = isExpanded ? expandedW : collapsedW;
        final height = isExpanded ? expandedH : collapsedH;
        // ponytail: use screen height directly; Overlay fills the screen
        // so its constraints match MediaQuery. Positioned must be a
        // direct child of Stack (the Overlay) to work correctly.
        final top = isExpanded
            ? (screen.height - height) / 2
            : screen.height -
                height -
                kBottomNavigationBarHeight -
                AppSpacing.sm;
        final left = (screen.width - width) / 2;

        return Positioned(
          top: top,
          left: left,
          width: width,
          height: height,
          child: GestureDetector(
            onVerticalDragEnd: isExpanded
                ? (d) {
                    if (d.primaryVelocity != null &&
                        d.primaryVelocity! > 300) {
                      _ctrl.collapse();
                    }
                  }
                : (d) {
                    if (d.primaryVelocity != null &&
                        d.primaryVelocity! < -300) {
                      _ctrl.expand();
                    }
                  },
            onTap: isExpanded
                ? null
                : () => Navigator.push(
                      context,
                      luminaRoute(
                        builder: (_) => VideoPlayerPage(
                          title: _ctrl.title,
                          videoUrl: _ctrl.videoUrl,
                          subject: _ctrl.subject,
                          existingController: _ctrl.videoController,
                          startInFullscreen: true,
                        ),
                      ),
                    ),
            child: AnimatedContainer(
              duration: animDur,
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(
                  isExpanded ? AppSpacing.radiusLg : AppSpacing.radiusMd,
                ),
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow,
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: isExpanded
                  ? _buildExpanded(vc, canShow, ar, cs, l10n)
                  : _buildCollapsed(vc, canShow, ar, cs, l10n),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCollapsed(
    VideoPlayerController? vc,
    bool canShow,
    double ar,
    ColorScheme cs,
    AppLocalizations l10n,
  ) {
    final tt = Theme.of(context).textTheme;
    Duration dur;
    Duration pos;
    try {
      dur = vc?.value.duration ?? Duration.zero;
      pos = vc?.value.position ?? Duration.zero;
    } catch (_) {
      dur = Duration.zero;
      pos = Duration.zero;
    }
    final progress = dur.inMilliseconds > 0
        ? pos.inMilliseconds / dur.inMilliseconds
        : 0.0;

    return Semantics(
      label: l10n.semanticsCloseMiniPlayer,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Row(
              children: [
                // Thumbnail
                SizedBox(
                  width: 96,
                  child: AspectRatio(
                    aspectRatio: ar,
                    child: canShow
                        ? VideoPlayer(vc!)
                        : Container(
                            color: cs.surfaceContainerHigh,
                            child: Icon(
                              Icons.play_circle_fill,
                              color: cs.onSurfaceVariant,
                              size: 28,
                            ),
                          ),
                  ),
                ),
                // Title
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    child: Text(
                      _ctrl.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.labelMedium?.copyWith(
                        color: cs.onSurface,
                        fontWeight: AppSpacing.weightStrong,
                      ),
                    ),
                  ),
                ),
                // Play/Pause
                Semantics(
                  label: l10n.semanticsTogglePlay,
                  button: true,
                  child: GestureDetector(
                    onTap: () {
                      if (vc == null) return;
                      vc.value.isPlaying ? vc.pause() : vc.play();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Icon(
                        vc != null && vc.value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: cs.onSurface,
                        size: 24,
                      ),
                    ),
                  ),
                ),
                // Close
                Semantics(
                  label: l10n.semanticsCloseMiniPlayer,
                  button: true,
                  child: GestureDetector(
                    onTap: _ctrl.stop,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Icon(
                        Icons.close,
                        color: cs.onSurfaceVariant,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Thin progress bar
          LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 2,
            backgroundColor: cs.outlineVariant,
            valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildExpanded(
    VideoPlayerController? vc,
    bool canShow,
    double ar,
    ColorScheme cs,
    AppLocalizations l10n,
  ) {
    final tt = Theme.of(context).textTheme;
    Duration dur;
    Duration pos;
    try {
      dur = vc?.value.duration ?? Duration.zero;
      pos = vc?.value.position ?? Duration.zero;
    } catch (_) {
      dur = Duration.zero;
      pos = Duration.zero;
    }

    return Column(
      children: [
        // Drag handle
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            ),
          ),
        ),
        // Video
        Expanded(
          child: GestureDetector(
            onTap: () => Navigator.push(
              context,
              luminaRoute(
                builder: (_) => VideoPlayerPage(
                  title: _ctrl.title,
                  videoUrl: _ctrl.videoUrl,
                  subject: _ctrl.subject,
                  existingController: _ctrl.videoController,
                  startInFullscreen: true,
                ),
              ),
            ),
            child: canShow
                ? Center(
                    child: AspectRatio(
                      aspectRatio: ar,
                      child: VideoPlayer(vc!),
                    ),
                  )
                : Center(
                    child: Icon(
                      Icons.play_circle_fill,
                      color: cs.onSurfaceVariant,
                      size: 48,
                    ),
                  ),
          ),
        ),
        // Title + Close
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _ctrl.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodyMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: AppSpacing.weightStrong,
                  ),
                ),
              ),
              Semantics(
                label: l10n.semanticsCloseMiniPlayer,
                button: true,
                child: GestureDetector(
                  onTap: _ctrl.stop,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: Icon(
                      Icons.close,
                      color: cs.onSurfaceVariant,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Seek bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape:
                  const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: cs.primary,
              inactiveTrackColor: cs.outlineVariant,
              thumbColor: cs.primary,
            ),
            child: Slider(
              value: dur.inMilliseconds > 0
                  ? pos.inMilliseconds
                      .toDouble()
                      .clamp(0.0, dur.inMilliseconds.toDouble())
                  : 0.0,
              max: dur.inMilliseconds > 0
                  ? dur.inMilliseconds.toDouble()
                  : 1.0,
              onChanged: (val) {
                vc?.seekTo(Duration(milliseconds: val.toInt()));
              },
            ),
          ),
        ),
        // Controls row
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.sm,
            right: AppSpacing.sm,
            bottom: AppSpacing.sm,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _controlButton(
                icon: Icons.replay_10,
                label: l10n.tooltipRewind10,
                cs: cs,
                onTap: () {
                  if (vc == null) return;
                  final newPos =
                      vc.value.position - const Duration(seconds: 10);
                  vc.seekTo(
                      newPos.isNegative ? Duration.zero : newPos);
                },
              ),
              _controlButton(
                icon: vc != null && vc.value.isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_filled,
                label: l10n.semanticsTogglePlay,
                cs: cs,
                size: 40,
                onTap: () {
                  if (vc == null) return;
                  vc.value.isPlaying ? vc.pause() : vc.play();
                },
              ),
              _controlButton(
                icon: Icons.forward_10,
                label: l10n.tooltipForward10,
                cs: cs,
                onTap: () {
                  if (vc == null) return;
                  final newPos =
                      vc.value.position + const Duration(seconds: 10);
                  if (newPos < vc.value.duration) vc.seekTo(newPos);
                },
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${_fmt(pos)} / ${_fmt(dur)}',
                style:
                    tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const Spacer(),
              _controlButton(
                icon: Icons.fullscreen,
                label: l10n.tooltipFullscreen,
                cs: cs,
                onTap: () => Navigator.push(
                  context,
                  luminaRoute(
                    builder: (_) => VideoPlayerPage(
                      title: _ctrl.title,
                      videoUrl: _ctrl.videoUrl,
                      subject: _ctrl.subject,
                      existingController: _ctrl.videoController,
                      startInFullscreen: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    required ColorScheme cs,
    required VoidCallback onTap,
    double size = 28,
  }) {
    return Semantics(
      label: label,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Icon(icon, color: cs.onSurface, size: size),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _attach());
    return const SizedBox.shrink();
  }
}
