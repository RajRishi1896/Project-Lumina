import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/network/api_client.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/services/activity_tracker.dart';

class VideoPlayerPage extends StatefulWidget {
  final String title;
  final String videoUrl;
  final String? subject;
  final VideoPlayerController? existingController;

  const VideoPlayerPage({
    super.key,
    required this.title,
    required this.videoUrl,
    this.subject,
    this.existingController,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  String? _error;
  bool _showControls = true;
  Timer? _hideTimer;
  bool _disposed = false;
  bool _ownsController = true;

  bool get _isLocal {
    final u = widget.videoUrl;
    if (u.startsWith('/data/') || u.startsWith('/storage/')) return true;
    return !u.startsWith('http') && !u.startsWith('/files/') && !u.startsWith('/api/');
  }

  @override
  void initState() {
    super.initState();
    ActivityTracker().startStudySession(subject: widget.subject);
    WakelockPlus.enable();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (widget.existingController != null &&
        widget.existingController!.value.isInitialized) {
      _controller = widget.existingController;
      _initialized = true;
      _ownsController = false;
    } else {
      _ownsController = true;
      _initPlayer();
    }
  }

  Future<void> _initPlayer({bool retry = false}) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      if (_isLocal) {
        final file = File(widget.videoUrl);
        if (!await file.exists()) {
          if (mounted) setState(() => _error = l10n.videoLocalFileNotFound);
          return;
        }
        _controller = VideoPlayerController.file(file);
      } else {
        String url = widget.videoUrl;
        if (url.startsWith('/')) {
          await ApiClient.ensureInitialized();
          url = '${ApiClient.baseUrl}$url';
        }
        _controller = VideoPlayerController.networkUrl(Uri.parse(url));
      }
      await _controller!.initialize();
      if (_disposed) {
        unawaited(_controller?.dispose());
        return;
      }
      _controller!.addListener(_onTick);
      if (mounted) {
        setState(() => _initialized = true);
        unawaited(_controller!.play());
        _startHideTimer();
      }
    } catch (e) {
      if (!retry && mounted) {
        _controller?.removeListener(_onTick);
        unawaited(_controller?.dispose());
        _controller = null;
        await _initPlayer(retry: true);
      } else if (mounted) {
        setState(() => _error = l10n.videoFailedToLoad(e.toString()));
      }
    }
  }

  void _onTick() {
    if (_disposed || !mounted || _controller == null) return;
    setState(() {});
  }

  void _togglePlay() {
    if (_controller == null) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
    _startHideTimer();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    setState(() => _showControls = true);
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && (_controller?.value.isPlaying ?? false)) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleFullscreen() {
    if (_controller == null) return;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    if (isLandscape) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void _retry() {
    setState(() {
      _error = null;
      _initialized = false;
    });
    _controller?.dispose();
    _controller = null;
    _initPlayer();
  }

  @override
  void dispose() {
    _disposed = true;
    _hideTimer?.cancel();
    ActivityTracker().endStudySession();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (_ownsController) {
      _controller?.removeListener(_onTick);
      _controller?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
        backgroundColor: cs.surfaceContainerHighest,
        appBar: _showControls
            ? AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: l10n.tooltipBackToResource,
                ),
                title: Text(widget.title),
                backgroundColor: cs.surfaceContainerHighest,
                foregroundColor: cs.onSurface,
              )
            : null,
        body: _buildBody(l10n, cs),
    );
  }

  Widget _buildBody(AppLocalizations l10n, ColorScheme cs) {
    final tt = Theme.of(context).textTheme;
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.section),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: cs.error),
              const SizedBox(height: AppSpacing.md),
              Text(_error!,
                  style: tt.bodyLarge?.copyWith(color: cs.onSurface),
                  textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.lg),
              IconButton.filled(
                onPressed: _retry,
                icon: const Icon(Icons.refresh),
                tooltip: l10n.buttonRetry,
              ),
            ],
          ),
        ),
      );
    }

    if (!_initialized || _controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return GestureDetector(
      onTap: _startHideTimer,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: VideoPlayer(_controller!),
            ),
          ),
          if (_showControls) _buildOverlay(l10n, cs),
          if (!_showControls)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildProgressBar(),
            ),
        ],
      ),
    );
  }

  Widget _buildOverlay(AppLocalizations l10n, ColorScheme cs) {
    final v = _controller!.value;
    final pos = v.position;
    final dur = v.duration;
    final tt = Theme.of(context).textTheme;

    return AnimatedOpacity(
      opacity: _showControls ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        // Solid theme token as the video-control scrim -- never alpha-on-text.
        color: cs.surfaceContainerHighest,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () {
                    final newPos = pos - const Duration(seconds: 10);
                    _controller!.seekTo(
                        newPos.isNegative ? Duration.zero : newPos);
                    _startHideTimer();
                  },
                  icon: Icon(Icons.replay_10, color: cs.onSurface, size: 36),
                  tooltip: l10n.tooltipRewind10,
                ),
                const SizedBox(width: AppSpacing.xl),
                IconButton(
                  onPressed: _togglePlay,
                  icon: Icon(
                    v.isPlaying ? Icons.pause_circle : Icons.play_circle,
                    color: cs.onSurface,
                    size: 64,
                  ),
                  tooltip: l10n.semanticsTogglePlay,
                ),
                const SizedBox(width: AppSpacing.xl),
                IconButton(
                  onPressed: () {
                    final newPos = pos + const Duration(seconds: 10);
                    if (newPos < dur) _controller!.seekTo(newPos);
                    _startHideTimer();
                  },
                  icon: Icon(Icons.forward_10, color: cs.onSurface, size: 36),
                  tooltip: l10n.tooltipForward10,
                ),
              ],
            ),
            const Spacer(),
            _buildProgressBar(),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Text(_fmt(pos),
                      style: tt.bodySmall?.copyWith(color: cs.onSurface)),
                  const Spacer(),
                  IconButton(
                    onPressed: _toggleFullscreen,
                    icon: Icon(
                      MediaQuery.of(context).orientation == Orientation.landscape
                          ? Icons.fullscreen_exit
                          : Icons.fullscreen,
                      color: cs.onSurface,
                      size: 24,
                    ),
                    tooltip: l10n.tooltipFullscreen,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    final v = _controller!.value;
    final dur = v.duration;
    if (dur.inMilliseconds == 0) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 2,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        activeTrackColor: Theme.of(context).colorScheme.primary,
        inactiveTrackColor: cs.outlineVariant,
        thumbColor: Theme.of(context).colorScheme.primary,
      ),
      child: Slider(
        value: v.position.inMilliseconds
            .toDouble()
            .clamp(0.0, dur.inMilliseconds.toDouble()),
        max: dur.inMilliseconds.toDouble(),
        onChanged: (val) {
          _controller!.seekTo(Duration(milliseconds: val.toInt()));
          _startHideTimer();
        },
      ),
    );
  }
}
