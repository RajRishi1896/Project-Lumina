import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// A singleton controller that manages the picture-in-picture mini-player overlay.
///
/// Holds a reference to the active [VideoPlayerController] so it can be
/// transferred between the full-screen [VideoPlayerPage] and the floating
/// [MiniPlayerWidget] without re-initialising the video stream.
///
/// Extends [ChangeNotifier] so widgets can listen for visibility changes.
class MiniPlayerController extends ChangeNotifier {
  static final MiniPlayerController _instance = MiniPlayerController._internal();

  /// Returns the singleton [MiniPlayerController] instance.
  factory MiniPlayerController() => _instance;
  MiniPlayerController._internal();

  VideoPlayerController? _videoController;
  String _title = '';
  String _videoUrl = '';
  String _subject = '';
  bool _active = false;
  bool _quizActive = false;

  bool get isActive => _active;

  /// Whether a quiz is currently active (mini-player should hide).
  bool get isQuizActive => _quizActive;

  String get title => _title;

  /// The video source URL associated with the active session.
  String get videoUrl => _videoUrl;

  /// The subject associated with the active session, threaded into study
  /// tracking when the video is reopened from the overlay.
  String get subject => _subject;

  /// The active [VideoPlayerController], or `null` when no video is playing.
  VideoPlayerController? get videoController => _videoController;

  /// Activates the mini-player with the given [title], [videoUrl], and controller.
  ///
  /// Replaces any previous session and notifies listeners immediately. A
  /// different previous controller is disposed so ghost streams never pile up.
  void start(String title, String videoUrl, VideoPlayerController videoController, {String? subject}) {
    if (_videoController != null && !identical(_videoController, videoController)) {
      _videoController!.removeListener(_onVideoEnded);
      _videoController!.dispose();
    }
    _title = title;
    _videoUrl = videoUrl;
    _subject = subject ?? '';
    _videoController = videoController;
    videoController.addListener(_onVideoEnded);
    _active = true;
    notifyListeners();
  }

  /// Stops playback, disposes the controller, and hides the overlay.
  void stop() {
    _videoController?.removeListener(_onVideoEnded);
    _videoController?.dispose();
    _videoController = null;
    _active = false;
    notifyListeners();
  }

  /// Retires the session when the video finishes so the overlay never shows
  /// a frozen last frame indefinitely (mirrors the full player's exit path).
  void _onVideoEnded() {
    final vc = _videoController;
    if (vc != null && vc.value.isCompleted) stop();
  }

  /// Sets the quiz-active flag. When `true` the mini-player widget hides and
  /// the video pauses so audio never leaks into exam mode; it resumes (unless
  /// the video ended) when the flag clears.
  void setQuizActive(bool value) {
    if (_quizActive == value) return;
    _quizActive = value;
    final vc = _videoController;
    if (vc == null || !vc.value.isInitialized) return;
    if (value) {
      vc.pause();
    } else if (!vc.value.isCompleted) {
      unawaited(vc.play());
    }
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
