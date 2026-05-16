import 'dart:io';
import 'package:flutter/material.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';
import '../../../core/constants/lumina_colors.dart';

class VideoView extends StatefulWidget {
  final String url;
  final bool isLocal;

  const VideoView({
    super.key,
    required this.url,
    this.isLocal = false,
  });

  @override
  State<VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<VideoView> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    if (widget.isLocal) {
      _videoPlayerController = VideoPlayerController.file(File(widget.url));
    } else {
      _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    }

    await _videoPlayerController.initialize();

    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController,
      autoPlay: true,
      looping: false,
      aspectRatio: _videoPlayerController.value.aspectRatio,
      materialProgressColors: ChewieProgressColors(
        playedColor: LuminaColors.academicTeal,
        handleColor: LuminaColors.academicTeal,
        backgroundColor: LuminaColors.outline,
        bufferedColor: LuminaColors.academicTeal.withOpacity(0.3),
      ),
      placeholder: Container(
        color: Colors.black,
      ),
      autoInitialize: true,
    );

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          'LECTURE PLAYER',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
        ),
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: _chewieController != null &&
                _chewieController!.videoPlayerController.value.isInitialized
            ? Chewie(
                controller: _chewieController!,
              )
            : const CircularProgressIndicator(
                color: LuminaColors.academicTeal,
              ),
      ),
    );
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }
}
