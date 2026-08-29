import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// A singleton controller that manages the picture-in-picture mini-player overlay.
///
/// Holds a reference to the active [VideoPlayerController] so it can be
/// transferred between the full-screen [VideoPlayerPage] and the floating
/// mini-player without re-initialising the video stream.
///
/// Uses an [OverlayEntry] so the mini-player renders above all pushed pages.
class MiniPlayerController extends ChangeNotifier {
  static final MiniPlayerController _instance = MiniPlayerController._internal();
  factory MiniPlayerController() => _instance;
  MiniPlayerController._internal();

  VideoPlayerController? _videoController;
  String _title = '';
  String _videoUrl = '';
  String _subject = '';
  bool _active = false;
  bool _expanded = false;
  bool _quizActive = false;
  OverlayEntry? _overlayEntry;

  bool get isActive => _active;
  bool get isExpanded => _expanded;
  bool get isQuizActive => _quizActive;
  String get title => _title;
  String get videoUrl => _videoUrl;
  String get subject => _subject;
  VideoPlayerController? get videoController => _videoController;

  /// Activates the mini-player with the given parameters.
  void start(String title, String videoUrl, VideoPlayerController videoController, {String? subject, OverlayEntry? overlayEntry}) {
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
    _expanded = false;
    _overlayEntry = overlayEntry;
    notifyListeners();
  }

  /// Stops playback, disposes the controller, and hides the overlay.
  void stop() {
    _videoController?.removeListener(_onVideoEnded);
    _videoController?.dispose();
    _videoController = null;
    _active = false;
    _expanded = false;
    _overlayEntry?.remove();
    _overlayEntry = null;
    notifyListeners();
  }

  /// Expands the mini-player to the larger panel view.
  void expand() {
    if (_expanded) return;
    _expanded = true;
    _overlayEntry?.markNeedsBuild();
    notifyListeners();
  }

  /// Collapses the mini-player back to the compact bar.
  void collapse() {
    if (!_expanded) return;
    _expanded = false;
    _overlayEntry?.markNeedsBuild();
    notifyListeners();
  }

  /// Toggles between collapsed and expanded states.
  void toggleExpanded() => _expanded ? collapse() : expand();

  /// Updates the overlay entry reference (called when overlay is rebuilt).
  void setOverlayEntry(OverlayEntry? entry) {
    _overlayEntry = entry;
  }

  void _onVideoEnded() {
    final vc = _videoController;
    if (vc != null && vc.value.isCompleted) stop();
  }

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
    _overlayEntry?.markNeedsBuild();
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
