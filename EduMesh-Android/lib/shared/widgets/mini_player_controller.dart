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
  bool _active = false;
  bool _quizActive = false;

  /// Whether the mini-player overlay is currently visible.
  bool get isActive => _active;

  /// Whether a quiz is currently active (mini-player should hide).
  bool get isQuizActive => _quizActive;

  /// The video title displayed in the mini-player.
  String get title => _title;

  /// The video source URL associated with the active session.
  String get videoUrl => _videoUrl;

  /// The active [VideoPlayerController], or `null` when no video is playing.
  VideoPlayerController? get videoController => _videoController;

  /// Activates the mini-player with the given [title], [videoUrl], and controller.
  ///
  /// Replaces any previous session and notifies listeners immediately.
  void start(String title, String videoUrl, VideoPlayerController videoController) {
    _title = title;
    _videoUrl = videoUrl;
    _videoController = videoController;
    _active = true;
    notifyListeners();
  }

  /// Stops playback, disposes the controller, and hides the overlay.
  void stop() {
    _videoController?.dispose();
    _videoController = null;
    _active = false;
    notifyListeners();
  }

  /// Hides the overlay without disposing the video controller.
  ///
  /// Used when the user navigates back to the full-screen page so the same
  /// controller can be reused.
  void closeOnlyOverlay() {
    _active = false;
    notifyListeners();
  }

  /// Sets the quiz-active flag. When `true` the mini-player widget hides.
  void setQuizActive(bool value) {
    _quizActive = value;
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
