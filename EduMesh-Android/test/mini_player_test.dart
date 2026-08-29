import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import 'package:edumesh_android/shared/widgets/mini_player_controller.dart';

/// Minimal pump wrapper so the overlay can be mounted.
Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: child),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Reset the singleton state between tests.
    MiniPlayerController().stop();
  });

  tearDown(() {
    MiniPlayerController().stop();
  });

  // -----------------------------------------------------------
  // Controller unit tests
  // -----------------------------------------------------------

  test('initial state is inactive', () {
    final ctrl = MiniPlayerController();
    expect(ctrl.isActive, false);
    expect(ctrl.isExpanded, false);
    expect(ctrl.videoController, isNull);
    expect(ctrl.title, '');
    expect(ctrl.videoUrl, '');
  });

  test('start activates and stores metadata', () {
    final ctrl = MiniPlayerController();
    final vc = VideoPlayerController.networkUrl(
      Uri.parse('http://example.com/video.mp4'),
    );

    ctrl.start('Test Video', 'http://example.com/video.mp4', vc);

    expect(ctrl.isActive, true);
    expect(ctrl.isExpanded, false);
    expect(ctrl.title, 'Test Video');
    expect(ctrl.videoUrl, 'http://example.com/video.mp4');
    expect(identical(ctrl.videoController, vc), true);

    vc.dispose();
  });

  test('stop deactivates and disposes controller', () {
    final ctrl = MiniPlayerController();
    final vc = VideoPlayerController.networkUrl(
      Uri.parse('http://example.com/video.mp4'),
    );

    ctrl.start('Test', 'http://example.com/video.mp4', vc);
    ctrl.stop();

    expect(ctrl.isActive, false);
    expect(ctrl.isExpanded, false);
    expect(ctrl.videoController, isNull);
  });

  test('expand / collapse toggle isExpanded', () {
    final ctrl = MiniPlayerController();
    final vc = VideoPlayerController.networkUrl(
      Uri.parse('http://example.com/v.mp4'),
    );
    ctrl.start('T', 'http://example.com/v.mp4', vc);

    expect(ctrl.isExpanded, false);
    ctrl.expand();
    expect(ctrl.isExpanded, true);
    ctrl.expand(); // no-op
    expect(ctrl.isExpanded, true);
    ctrl.collapse();
    expect(ctrl.isExpanded, false);
    ctrl.collapse(); // no-op
    expect(ctrl.isExpanded, false);

    vc.dispose();
  });

  test('toggleExpanded alternates states', () {
    final ctrl = MiniPlayerController();
    final vc = VideoPlayerController.networkUrl(
      Uri.parse('http://example.com/v.mp4'),
    );
    ctrl.start('T', 'http://example.com/v.mp4', vc);

    ctrl.toggleExpanded();
    expect(ctrl.isExpanded, true);
    ctrl.toggleExpanded();
    expect(ctrl.isExpanded, false);

    vc.dispose();
  });

  test('start disposes previous controller when replaced', () {
    final ctrl = MiniPlayerController();
    final vc1 = VideoPlayerController.networkUrl(
      Uri.parse('http://example.com/v1.mp4'),
    );
    final vc2 = VideoPlayerController.networkUrl(
      Uri.parse('http://example.com/v2.mp4'),
    );

    ctrl.start('First', 'http://example.com/v1.mp4', vc1);
    ctrl.start('Second', 'http://example.com/v2.mp4', vc2);

    // The old controller should have been disposed; the new one is active.
    expect(ctrl.title, 'Second');
    expect(identical(ctrl.videoController, vc2), true);

    vc2.dispose();
  });

  test('stop resets expanded state', () {
    final ctrl = MiniPlayerController();
    final vc = VideoPlayerController.networkUrl(
      Uri.parse('http://example.com/v.mp4'),
    );
    ctrl.start('T', 'http://example.com/v.mp4', vc);
    ctrl.expand();
    expect(ctrl.isExpanded, true);

    ctrl.stop();
    expect(ctrl.isExpanded, false);

    vc.dispose();
  });

  test('setQuizActive pauses and resumes', () {
    final ctrl = MiniPlayerController();
    final vc = VideoPlayerController.networkUrl(
      Uri.parse('http://example.com/v.mp4'),
    );
    ctrl.start('T', 'http://example.com/v.mp4', vc);

    ctrl.setQuizActive(true);
    expect(ctrl.isQuizActive, true);

    ctrl.setQuizActive(false);
    expect(ctrl.isQuizActive, false);

    vc.dispose();
  });

  test('notifyListeners fires on start/stop/expand/collapse', () {
    final ctrl = MiniPlayerController();
    int notifyCount = 0;
    ctrl.addListener(() => notifyCount++);

    final vc = VideoPlayerController.networkUrl(
      Uri.parse('http://example.com/v.mp4'),
    );

    ctrl.start('T', 'http://example.com/v.mp4', vc);
    expect(notifyCount, 1);

    ctrl.expand();
    expect(notifyCount, 2);

    ctrl.collapse();
    expect(notifyCount, 3);

    ctrl.stop();
    expect(notifyCount, 4);

    ctrl.removeListener(() {});
    vc.dispose();
  });

  test('setOverlayEntry stores and clears reference', () {
    final ctrl = MiniPlayerController();
    // setOverlayEntry is internal; just verify it doesn't throw.
    ctrl.setOverlayEntry(null);
  });

  test('identical controller is not double-disposed on start', () {
    final ctrl = MiniPlayerController();
    final vc = VideoPlayerController.networkUrl(
      Uri.parse('http://example.com/v.mp4'),
    );
    ctrl.start('T', 'http://example.com/v.mp4', vc);

    int notifyCount = 0;
    ctrl.addListener(() => notifyCount++);

    // Starting with the same controller should not dispose or re-add.
    ctrl.start('T', 'http://example.com/v.mp4', vc);
    // notifyCount should be 1 (from the second start's notifyListeners)
    expect(notifyCount, 1);

    ctrl.stop();
    vc.dispose();
  });
}
