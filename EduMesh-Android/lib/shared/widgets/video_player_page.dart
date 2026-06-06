import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/network/api_client.dart';
import 'mini_player_controller.dart';

/// A full-screen video player page backed by [Chewie] with PiP support.
///
/// Supports both local files and network URLs. Playback position is
/// persisted to [SharedPreferences] and restored on load. When the user
/// navigates back, the video may enter the mini-player overlay via
/// [MiniPlayerController] instead of being discarded.
class VideoPlayerPage extends StatefulWidget {
  /// The display title shown in the app bar.
  final String title;

  /// The video source path or URL.
  ///
  /// When the value starts with `/` or `http`, it is treated as a remote URL
  /// and routed through [ApiClient] for streaming support. Otherwise it is
  /// treated as a local file path.
  final String videoUrl;

  /// An optional externally-owned [VideoPlayerController] to reuse.
  ///
  /// When provided together with [existingChewie], the page skips player
  /// initialisation and uses the given controllers directly.
  final VideoPlayerController? existingController;

  /// An optional externally-owned [ChewieController] to reuse.
  final ChewieController? existingChewie;

  const VideoPlayerPage({
    super.key,
    required this.title,
    required this.videoUrl,
    this.existingController,
    this.existingChewie,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _initialized = false;
  String? _error;

  String get _positionKey => 'vid_pos_${widget.videoUrl}';

  bool get _shouldPiP =>
      widget.existingController == null && widget.existingChewie == null;

  @override
  void initState() {
    super.initState();
    if (widget.existingController != null && widget.existingChewie != null) {
      _videoController = widget.existingController;
      _chewieController = widget.existingChewie;
      _initialized = true;
      return;
    }
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final cs = Theme.of(context).colorScheme;
    try {
      final isLocal = !widget.videoUrl.startsWith('/') && !widget.videoUrl.startsWith('http');
      if (isLocal) {
        final file = File(widget.videoUrl);
        if (!await file.exists()) {
          if (mounted) setState(() => _error = 'Local file not found');
          return;
        }
        _videoController = VideoPlayerController.file(file);
      } else {
        await ApiClient.ensureInitialized();
        final base = ApiClient.dio.options.baseUrl.replaceAll(RegExp(r'/api/?$'), '');
        var streamUrl = widget.videoUrl.startsWith('/') ? '$base$widget.videoUrl' : widget.videoUrl;
        if (streamUrl.contains('/files/')) {
          streamUrl = streamUrl.replaceFirst('/files/', '/api/stream/');
        }
        _videoController = VideoPlayerController.networkUrl(Uri.parse(streamUrl));
      }
      await _videoController!.initialize();

      final prefs = await SharedPreferences.getInstance();
      final savedPos = prefs.getDouble(_positionKey) ?? 0.0;
      if (savedPos > 0 && savedPos < _videoController!.value.duration.inMilliseconds / 1000) {
        await _videoController!.seekTo(Duration(milliseconds: (savedPos * 1000).toInt()));
      }

      final playedColor = cs.primary;
      final bgColor = cs.surfaceContainerHigh;
      _chewieController = ChewieController(
        videoPlayerController: _videoController!,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: playedColor,
          handleColor: playedColor,
          backgroundColor: bgColor,
        ),
      );
      if (mounted) setState(() => _initialized = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load video: $e');
    }
  }

  Future<void> _savePosition() async {
    if (_videoController == null || !_videoController!.value.isInitialized) return;
    final pos = _videoController!.value.position.inMilliseconds / 1000.0;
    final dur = _videoController!.value.duration.inMilliseconds / 1000.0;
    if (pos > 0 && pos < dur - 5) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_positionKey, pos);
    }
  }

  void _enterMiniPlayer() {
    if (!_shouldPiP || _videoController == null || _chewieController == null) return;
    _savePosition();
    MiniPlayerController().start(
      widget.title,
      widget.videoUrl,
      _videoController!,
      _chewieController!,
    );
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    if (widget.existingController == null) {
      _savePosition();
    }
    if (widget.existingController == null && !MiniPlayerController().isActive) {
      _chewieController?.dispose();
      _videoController?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _enterMiniPlayer();
      },
      child: Scaffold(
        backgroundColor: cs.surfaceContainerHighest,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _enterMiniPlayer,
          ),
          title: Text(widget.title),
          backgroundColor: cs.surfaceContainerHighest,
          foregroundColor: cs.onSurface,
          actions: [
            if (_shouldPiP && _initialized)
              IconButton(
                icon: const Icon(Icons.picture_in_picture_alt),
                tooltip: 'Mini player',
                onPressed: _enterMiniPlayer,
              ),
          ],
        ),
        body: Center(
          child: _error != null
              ? Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(_error!,
                      style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7)),
                      textAlign: TextAlign.center),
                )
              : _initialized && _chewieController != null
                  ? Chewie(controller: _chewieController!)
                  : CircularProgressIndicator(color: cs.onSurface),
        ),
      ),
    );
  }
}
