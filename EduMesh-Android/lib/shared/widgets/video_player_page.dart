import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:edumesh_android/core/system_ui/lumina_system_ui.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/pip_helper.dart';
import '../../l10n/app_localizations.dart';
import '../../core/services/activity_tracker.dart';
import '../widgets/mini_player_controller.dart';

const _speedOptions = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

/// A full-screen video player with playback speed, fullscreen, and
/// seek-preview controls.
class VideoPlayerPage extends StatefulWidget {
  final String title;

  /// The video source URL, or a local file path.
  final String videoUrl;

  /// The subject associated with this video, passed to activity tracking.
  final String? subject;

  /// An already-initialized [VideoPlayerController] to adopt instead of
  /// creating a new one.
  final VideoPlayerController? existingController;

  /// Whether the page opens directly in fullscreen (landscape) mode.
  final bool startInFullscreen;

  /// Called exactly once when playback reaches the end of the video.
  final VoidCallback? onEnded;

  const VideoPlayerPage({
    super.key,
    required this.title,
    required this.videoUrl,
    this.subject,
    this.existingController,
    this.startInFullscreen = false,
    this.onEnded,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _firstFrame = false;
  String? _error;
  // Generation token: bumped on close/retry/dispose so an in-flight
  // _initPlayer that finishes late can neither revive playback nor leak
  // its controller (the audio-after-back bug).
  int _initGen = 0;
  bool _showControls = true;
  Timer? _hideTimer;
  bool _disposed = false;
  bool _ownsController = true;
  bool _exitRequested = false;
  bool _isFullscreen = false;
  int _uiPushes = 0;
  double _playbackSpeed = 1.0;
  _SeekFeedback? _seekFeedback;
  bool _feedbackVisible = false;
  Timer? _feedbackTimer;
  double? _dragStartMs;
  bool _previewDragging = false;
  _PreviewSheet? _preview;
  bool _previewsUnavailable = false;
  bool _previewLoading = false;
  bool _inPiP = false;
  bool _lifecyclePushed = false;
  bool _endedFired = false;

  /// Position in seconds, updated by the tick listener. Only drives the
  /// lightweight position text and progress bar — no full-overlay rebuild.
  final ValueNotifier<int> _posSeconds = ValueNotifier(0);

  bool get _isLocal {
    final u = widget.videoUrl;
    if (u.startsWith('/data/') || u.startsWith('/storage/')) return true;
    return !u.startsWith('http') && !u.startsWith('/files/') && !u.startsWith('/api/');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPiP();
    ActivityTracker().startStudySession(subject: widget.subject);
    WakelockPlus.enable();
    _isFullscreen = widget.startInFullscreen;
    _uiPushes++;
    LuminaSystemUi.push(
      orientations: _isFullscreen
          ? const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : [
              DeviceOrientation.portraitUp,
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ],
      mode: SystemUiMode.edgeToEdge,
    );
    if (widget.existingController != null &&
        widget.existingController!.value.isInitialized) {
      _controller = widget.existingController;
      _initialized = true;
      _ownsController = false;
      // An adopted controller already rendered frames elsewhere unless it
      // never advanced past zero.
      _firstFrame =
          widget.existingController!.value.position.inMilliseconds > 0;
      _controller!.addListener(_onTick);
    } else {
      _ownsController = true;
      // Deferred: _initPlayer reads AppLocalizations via context, and
      // dependOnInheritedWidget is illegal until the first frame mounts.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _initPlayer();
      });
    }
  }

  Future<void> _initPiP() async {
    final pip = PiPHelper();
    await pip.init();
    pip.onModeChanged = (inPiP) {
      if (!mounted) return;
      setState(() => _inPiP = inPiP);
      if (!inPiP) {
        _startHideTimer();
        // Exiting PiP — if the app is in foreground, push system UI to
        // restore orientations and chrome (didChangeAppLifecycleState
        // may not fire if the transition is fast).
        if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed && !_lifecyclePushed) {
          LuminaSystemUi.push(
            orientations: _isFullscreen
                ? const [
                    DeviceOrientation.landscapeLeft,
                    DeviceOrientation.landscapeRight,
                  ]
                : [
                    DeviceOrientation.portraitUp,
                    DeviceOrientation.landscapeLeft,
                    DeviceOrientation.landscapeRight,
                  ],
            mode: SystemUiMode.edgeToEdge,
          );
          _lifecyclePushed = true;
        }
      }
    };
    pip.onAction = (action) {
      if (!mounted || _controller == null) return;
      switch (action) {
        case 'play_pause':
          _togglePlay();
          _syncPiPActions();
          break;
        case 'forward':
          final pos = _controller!.value.position;
          final dur = _controller!.value.duration;
          final target = pos + const Duration(seconds: 10);
          _controller!.seekTo(target < dur ? target : dur);
          break;
      }
    };
  }

  void _syncPiPActions() {
    if (_controller == null) return;
    PiPHelper().updatePiPActions(isPlaying: _controller!.value.isPlaying);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    if (state == AppLifecycleState.resumed && !_inPiP) {
      // Returned from background (not PiP). Restore system UI.
      if (!_lifecyclePushed) {
        LuminaSystemUi.push(
          orientations: _isFullscreen
              ? const [
                  DeviceOrientation.landscapeLeft,
                  DeviceOrientation.landscapeRight,
                ]
              : [
                  DeviceOrientation.portraitUp,
                  DeviceOrientation.landscapeLeft,
                  DeviceOrientation.landscapeRight,
                ],
          mode: SystemUiMode.edgeToEdge,
        );
        _lifecyclePushed = true;
      }
    }
  }

  Future<void> _initPlayer({bool retry = false}) async {
    final myGen = _initGen;
    final l10n = AppLocalizations.of(context)!;
    VideoPlayerController? controller;
    try {
      if (_isLocal) {
        final file = File(widget.videoUrl);
        if (!await file.exists()) {
          if (mounted && myGen == _initGen) {
            setState(() => _error = l10n.videoLocalFileNotFound);
          }
          return;
        }
        controller = VideoPlayerController.file(file);
      } else {
        String url = widget.videoUrl;
        if (url.startsWith('/')) {
          await ApiClient.ensureInitialized();
          url = '${ApiClient.baseUrl}$url';
        }
        controller = VideoPlayerController.networkUrl(Uri.parse(url));
      }
      await controller.initialize();
      // Close/retry/dispose ran mid-initialize: drop the orphan instead of
      // adopting it (adopting revived audio after back navigation).
      if (_disposed || myGen != _initGen) {
        try {
          await controller.dispose();
        } catch (_) {}
        return;
      }
      _controller = controller;
      controller = null;
      _controller!.addListener(_onTick);
      if (mounted) {
        setState(() => _initialized = true);
        // Autoplay is required to produce frames, but the loading overlay
        // stays up until the first frame actually renders (see _onTick).
        unawaited(_controller!.play());
        _startHideTimer();
      }
    } catch (e) {
      try {
        await controller?.dispose();
      } catch (_) {}
      if (_disposed || myGen != _initGen) return;
      if (!retry && mounted) {
        _initGen++;
        _controller = null;
        await _initPlayer(retry: true);
      } else if (mounted) {
        setState(() => _error = l10n.videoFailedToLoad(e.toString()));
      }
    }
  }

  /// Tick listener: updates only the lightweight position notifier.
  /// No full-overlay rebuild — the ValueListenableBuilder on _posSeconds
  /// and the progress bar handle their own targeted rebuilds.
  /// Also latches _firstFrame once playback visibly advances so the loading
  /// overlay stays up until video (not just audio) is rendering.
  void _onTick() {
    if (_disposed || _controller == null) return;
    final v = _controller!.value;
    _posSeconds.value = v.position.inSeconds;
    if (!_firstFrame && _initialized && v.position.inMilliseconds > 0) {
      _firstFrame = true;
      if (mounted) setState(() {});
    }
    // Exact completion signal: playback ended (position reached duration).
    if (!_endedFired && _initialized && v.duration.inMilliseconds > 0 && v.position >= v.duration) {
      _endedFired = true;
      try {
        widget.onEnded?.call();
      } catch (_) {}
    }
  }

  void _togglePlay() {
    if (_controller == null) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
    if (_inPiP) _syncPiPActions();
    _startHideTimer();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (!_showControls) setState(() => _showControls = true);
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && (_controller?.value.isPlaying ?? false)) {
        setState(() => _showControls = false);
      }
    });
  }

  /// Single-tap behavior, YouTube-style: toggles the whole control layer
  /// (play/pause, ±10s, speed, PiP, fullscreen, progress). Tapping while
  /// visible hides immediately instead of just restarting the timer.
  void _toggleControls() {
    if (_showControls) {
      _hideTimer?.cancel();
      setState(() => _showControls = false);
    } else {
      _startHideTimer();
    }
  }

  void _toggleFullscreen() {
    if (_controller == null) return;
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      _uiPushes++;
      LuminaSystemUi.push(
        orientations: const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
        mode: SystemUiMode.edgeToEdge,
      );
    } else {
      // Unwind the landscape claim; the page's entry config applies again.
      LuminaSystemUi.restore();
      _uiPushes--;
    }
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Duration _clampSeek(Duration pos, Duration dur) {
    final ms = pos.inMilliseconds.clamp(0, dur.inMilliseconds);
    return Duration(milliseconds: ms);
  }

  void _setSeekFeedback({
    required String text,
    IconData? icon,
    required Alignment alignment,
  }) {
    _feedbackTimer?.cancel();
    setState(() {
      _seekFeedback = _SeekFeedback(icon: icon, text: text, alignment: alignment);
      _feedbackVisible = true;
    });
    _feedbackTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _feedbackVisible = false);
    });
  }

  void _onDoubleTapDown(TapDownDetails details) {
    final v = _controller!.value;
    final dur = v.duration;
    final rewind =
        details.globalPosition.dx < MediaQuery.of(context).size.width / 2;
    final target = rewind
        ? v.position - const Duration(seconds: 10)
        : v.position + const Duration(seconds: 10);
    final clamped = _clampSeek(target, dur);
    _controller!.seekTo(clamped);
    _setSeekFeedback(
      icon: rewind ? Icons.replay_10 : Icons.forward_10,
      text: _fmt(clamped),
      alignment: rewind ? Alignment.centerLeft : Alignment.centerRight,
    );
    _startHideTimer();
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    _dragStartMs = _controller!.value.position.inMilliseconds.toDouble();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final v = _controller!.value;
    final durMs = v.duration.inMilliseconds;
    if (_dragStartMs == null || durMs == 0) return;
    final width = MediaQuery.of(context).size.width;
    if (width <= 0) return;
    final targetMs = (_dragStartMs! + (details.delta.dx / width) * durMs)
        .clamp(0.0, durMs.toDouble());
    final target = Duration(milliseconds: targetMs.round());
    _controller!.seekTo(target);
    _setSeekFeedback(text: _fmt(target), alignment: Alignment.center);
    _startHideTimer();
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    _feedbackTimer?.cancel();
    if (mounted) setState(() => _feedbackVisible = false);
  }

  String _speedLabel(AppLocalizations l10n, double speed) {
    final value =
        speed == speed.roundToDouble() ? speed.toInt().toString() : speed.toString();
    return l10n.videoSpeedValue(value);
  }

  Future<void> _showSpeedMenu() async {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final selected = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surfaceContainerHighest,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.5,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  l10n.videoPlaybackSpeed,
                  style: tt.titleMedium?.copyWith(color: cs.onSurface),
                ),
              ),
              for (final speed in _speedOptions)
                ListTile(
                  title: Text(_speedLabel(l10n, speed)),
                  trailing: speed == _playbackSpeed
                      ? Icon(Icons.check, color: cs.primary)
                      : null,
                  onTap: () => Navigator.of(ctx).pop(speed),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    _playbackSpeed = selected;
    await _controller!.setPlaybackSpeed(selected);
    if (mounted) setState(() {});
    _startHideTimer();
  }

  Future<void> _loadPreviewSheet() async {
    if (_preview != null || _previewsUnavailable || _previewLoading) return;
    _previewLoading = true;
    try {
      await ApiClient.ensureInitialized();
      final segments = Uri.parse(widget.videoUrl).pathSegments;
      final filename = segments.isEmpty ? widget.videoUrl : segments.last;
      final dot = filename.lastIndexOf('.');
      final base = dot > 0 ? filename.substring(0, dot) : filename;
      if (base.isEmpty) throw Exception('empty video id');
      final metaResp = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/video/previews/$base',
      );
      final meta = metaResp.data;
      if (meta == null) throw Exception('no preview metadata');
      final frameW = (meta['frame_w'] as num?)?.toInt() ?? 0;
      final frameH = (meta['frame_h'] as num?)?.toInt() ?? 0;
      final columns = (meta['columns'] as num?)?.toInt() ?? 0;
      final rows = (meta['rows'] as num?)?.toInt() ?? 0;
      final frames = (meta['frames'] as num?)?.toInt() ?? 0;
      final spriteUrl = meta['sprite_url'] as String?;
      if (frameW <= 0 ||
          frameH <= 0 ||
          columns <= 0 ||
          rows <= 0 ||
          frames < 1 ||
          spriteUrl == null) {
        throw Exception('bad preview metadata');
      }
      final spriteResp = await ApiClient.dio.get<List<int>>(
        spriteUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      final sprite = MemoryImage(Uint8List.fromList(spriteResp.data ?? const []));
      if (!mounted) return;
      setState(() {
        _preview = _PreviewSheet(
          frameW: frameW,
          frameH: frameH,
          columns: columns,
          rows: rows,
          frames: frames,
          sprite: sprite,
        );
      });
    } catch (_) {
      _previewsUnavailable = true;
    } finally {
      _previewLoading = false;
    }
  }

  /// Closes the player deterministically: timers cancelled, playback
  /// paused, listener detached, and the owned controller disposed
  /// synchronously so no audio can survive navigation. When this page
  /// adopted the mini-player's controller, that session ends instead.
  /// When in PiP, exits PiP first.
  void _closePlayer() {
    if (_exitRequested) return;
    _exitRequested = true;
    _initGen++;
    _hideTimer?.cancel();
    _feedbackTimer?.cancel();
    if (PiPHelper().isInPiP) {
      PiPHelper().exitPiP();
    }
    final c = _controller;
    _controller = null;
    if (c != null) {
      try {
        c.pause();
      } catch (_) {}
      try {
        c.removeListener(_onTick);
      } catch (_) {}
      final mini = MiniPlayerController();
      if (!_ownsController && identical(mini.videoController, c)) {
        mini.stop();
      } else if (_ownsController) {
        try {
          c.dispose();
        } catch (_) {}
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  /// Enters OS-level Picture-in-Picture mode. The video keeps playing in a
  /// system floating window while the user navigates the app.
  /// Does NOT set _exitRequested: the page stays alive behind PiP and the
  /// back button must keep working (setting it dead-locked _closePlayer).
  /// If the OS refuses PiP, falls back to the in-app mini-player so the
  /// button always visibly does something.
  Future<void> _minimize() async {
    if (_exitRequested || !_initialized || _controller == null) return;
    final c = _controller!;
    final ok = await PiPHelper()
        .enterPiP(isPlaying: c.value.isPlaying)
        .catchError((_) => false);
    if (ok || !mounted) return;
    try {
      c.removeListener(_onTick);
    } catch (_) {}
    MiniPlayerController()
        .start(widget.title, widget.videoUrl, c, subject: widget.subject);
    _ownsController = false;
    _controller = null;
    Navigator.of(context).pop();
  }

  void _retry() {
    _initGen++;
    _endedFired = false;
    setState(() {
      _error = null;
      _initialized = false;
      _firstFrame = false;
    });
    try {
      _controller?.removeListener(_onTick);
    } catch (_) {}
    try {
      _controller?.dispose();
    } catch (_) {}
    _controller = null;
    _initPlayer();
  }

  @override
  void dispose() {
    _disposed = true;
    _initGen++;
    WidgetsBinding.instance.removeObserver(this);
    PiPHelper().onModeChanged = null;
    PiPHelper().onAction = null;
    _hideTimer?.cancel();
    _feedbackTimer?.cancel();
    _posSeconds.dispose();
    ActivityTracker().endStudySession();
    WakelockPlus.disable();
    // Unwind every claim this page pushed (entry + fullscreen); the app
    // baseline returns when the stack empties, so the user's own rotation
    // setting applies again.
    while (_uiPushes > 0) {
      LuminaSystemUi.restore();
      _uiPushes--;
    }
    if (_lifecyclePushed) {
      LuminaSystemUi.restore();
      _lifecyclePushed = false;
    }
    if (_controller != null) {
      try {
        _controller!.removeListener(_onTick);
      } catch (_) {}
      if (_ownsController) {
        try {
          _controller!.dispose();
        } catch (_) {}
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closePlayer();
      },
      child: Scaffold(
        backgroundColor: cs.surfaceContainerHighest,
        // AppBar is ALWAYS present so the back button always works.
        // In fullscreen/PiP mode it hides; otherwise it's always reachable.
        appBar: !_isFullscreen && !_inPiP
            ? AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _closePlayer,
                  tooltip: l10n.tooltipBackToResource,
                ),
                title: Text(widget.title),
                backgroundColor: cs.surfaceContainerHighest,
                foregroundColor: cs.onSurface,
              )
            : null,
        body: _buildBody(l10n, cs),
      ),
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

    // No surface until initialized: building VideoPlayer on an
    // uninitialized controller shows a black texture while audio can
    // already play. Spinner until then.
    if (_controller == null || !_initialized) {
      return const Center(child: CircularProgressIndicator());
    }

    // NOTE: no placeholder UI while in OS PiP. The system PiP window
    // renders this page's activity surface, so the VideoPlayer must stay
    // mounted for the floating window to show video instead of a static
    // message. AppBar/controls stay hidden via _inPiP below.

    final aspect = _controller!.value.aspectRatio;
    // Single GestureDetector: double-tap for seek, horizontal drag for
    // scrub, single tap toggles controls.
    return GestureDetector(
      onTap: _toggleControls,
      onDoubleTapDown: _onDoubleTapDown,
      onHorizontalDragStart: _onHorizontalDragStart,
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Video surface — always visible once controller exists.
          Center(
            child: AspectRatio(
              aspectRatio: aspect == 0 ? 16 / 9 : aspect,
              child: VideoPlayer(_controller!),
            ),
          ),
          // Loading overlay: stays up until the first video frame renders,
          // not just until initialize() resolves (audio starts before the
          // decoder produces frames on low-end phones).
          if (!_initialized || !_firstFrame)
            Container(
              color: cs.surfaceContainerHighest,
              child: const Center(child: CircularProgressIndicator()),
            ),
          if (_seekFeedback != null && !_inPiP) _buildSeekFeedback(),
          if (_showControls && !_inPiP) _buildOverlay(l10n, cs),
          if ((!_showControls || _inPiP) && _initialized)
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
    final dur = v.duration;
    final tt = Theme.of(context).textTheme;

    return AnimatedOpacity(
      opacity: _showControls ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: ColoredBox(
        // Solid theme token as the video-control scrim: never alpha-on-text.
        color: cs.surfaceContainerHighest,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Spacer(),
            // Play/pause + seek buttons — rebuilds via ValueListenableBuilder
            // so only the play/pause icon flips, not the whole overlay.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () {
                    final newPos = v.position - const Duration(seconds: 10);
                    _controller!.seekTo(
                        newPos.isNegative ? Duration.zero : newPos);
                    _startHideTimer();
                  },
                  icon: Icon(Icons.replay_10, color: cs.onSurface, size: 36),
                  tooltip: l10n.tooltipRewind10,
                ),
                const SizedBox(width: AppSpacing.xl),
                ValueListenableBuilder<int>(
                  valueListenable: _posSeconds,
                  builder: (_, __, ___) {
                    final playing = _controller?.value.isPlaying ?? false;
                    return IconButton(
                      onPressed: _togglePlay,
                      icon: Icon(
                        playing ? Icons.pause_circle : Icons.play_circle,
                        color: cs.onSurface,
                        size: 64,
                      ),
                      tooltip: l10n.semanticsTogglePlay,
                    );
                  },
                ),
                const SizedBox(width: AppSpacing.xl),
                IconButton(
                  onPressed: () {
                    final newPos = v.position + const Duration(seconds: 10);
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
                  // Position text: rebuilds via ValueListenableBuilder only.
                  ValueListenableBuilder<int>(
                    valueListenable: _posSeconds,
                    builder: (_, sec, __) => Text(
                      _fmt(Duration(seconds: sec)),
                      style: tt.bodySmall?.copyWith(color: cs.onSurface),
                    ),
                  ),
                  const Spacer(),
                  Tooltip(
                    message: l10n.videoPlaybackSpeed,
                    child: TextButton(
                      onPressed: _showSpeedMenu,
                      style: TextButton.styleFrom(
                        foregroundColor: cs.onSurface,
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm),
                      ),
                      child: Text(
                        _speedLabel(l10n, _playbackSpeed),
                        style: tt.bodySmall?.copyWith(color: cs.onSurface),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _minimize,
                    icon: Icon(Icons.picture_in_picture_alt,
                        color: cs.onSurface, size: 24),
                    tooltip: l10n.buttonMinimizeVideo,
                  ),
                  IconButton(
                    onPressed: _toggleFullscreen,
                    icon: Icon(
                      _isFullscreen
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
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ValueListenableBuilder<int>(
            valueListenable: _posSeconds,
            builder: (_, __, ___) {
              final posMs = _controller!.value.position.inMilliseconds
                  .toDouble()
                  .clamp(0.0, dur.inMilliseconds.toDouble());
              return Slider(
                value: posMs,
                max: dur.inMilliseconds.toDouble(),
                onChangeStart: (val) {
                  setState(() => _previewDragging = true);
                  if (_preview == null && !_previewsUnavailable) {
                    unawaited(_loadPreviewSheet());
                  }
                },
                onChanged: (val) {
                  _controller!.seekTo(Duration(milliseconds: val.toInt()));
                  _startHideTimer();
                },
                onChangeEnd: (val) {
                  setState(() => _previewDragging = false);
                },
              );
            },
          ),
          if (_preview != null && _previewDragging)
            Positioned(
              bottom: AppSpacing.section + AppSpacing.md,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: _buildPreviewBubble(
                    _controller!.value.position.inMilliseconds.toDouble(),
                    _preview!,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPreviewBubble(double valueMs, _PreviewSheet p) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final durMs = _controller!.value.duration.inMilliseconds;
    final index = durMs == 0
        ? 0
        : (valueMs / durMs * p.frames).floor().clamp(0, p.frames - 1);
    final col = index % p.columns;
    final row = index ~/ p.columns;
    final ax = p.columns == 1 ? -1.0 : -1.0 + 2.0 * col / (p.columns - 1);
    final ay = p.rows == 1 ? -1.0 : -1.0 + 2.0 * row / (p.rows - 1);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.xs),
            child: SizedBox(
              width: p.frameW.toDouble(),
              height: p.frameH.toDouble(),
              child: Image(
                image: p.sprite,
                fit: BoxFit.none,
                width: p.frameW * p.columns.toDouble(),
                height: p.frameH * p.rows.toDouble(),
                alignment: Alignment(ax, ay),
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(_fmt(Duration(milliseconds: valueMs.round())),
              style: tt.labelSmall?.copyWith(color: cs.onSurface)),
        ],
      ),
    );
  }

  Widget _buildSeekFeedback() {
    final f = _seekFeedback!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Align(
      alignment: f.alignment,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: IgnorePointer(
          child: Semantics(
            liveRegion: true,
            label: f.text,
            child: AnimatedOpacity(
              opacity: _feedbackVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppSpacing.lg),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (f.icon != null) ...[
                      Icon(f.icon, color: cs.onSurface, size: 40),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    Text(f.text,
                        style: tt.bodyLarge?.copyWith(color: cs.onSurface)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SeekFeedback {
  const _SeekFeedback({
    this.icon,
    required this.text,
    required this.alignment,
  });

  final IconData? icon;
  final String text;
  final Alignment alignment;
}

class _PreviewSheet {
  const _PreviewSheet({
    required this.frameW,
    required this.frameH,
    required this.columns,
    required this.rows,
    required this.frames,
    required this.sprite,
  });

  final int frameW;
  final int frameH;
  final int columns;
  final int rows;
  final int frames;
  final MemoryImage sprite;
}
