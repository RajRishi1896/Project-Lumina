import 'dart:async';

import 'package:flutter/services.dart';

/// Central system-UI policy: the one place that talks to SystemChrome.
///
/// Pages that need a non-default orientation or bar mode `push` a config on
/// entry and call `restore` on exit; snapshots always unwind in order, so an
/// outgoing route's dispose can never clobber an incoming route's claim (the
/// last-writer-wins race of raw unawaited SystemChrome calls). With no
/// snapshots left, [restore] reapplies the app baseline: edge-to-edge with no
/// orientation claim, matching the launch look on Android 16.
class LuminaSystemUi {
  LuminaSystemUi._();

  static (List<DeviceOrientation>, SystemUiMode)? _current;
  static final List<(List<DeviceOrientation>, SystemUiMode)> _stack = [];
  static Future<void> _chain = Future.value();

  /// Applies the app baseline (edge-to-edge, orientation released). Call once
  /// at startup; also what an over-popped [restore] falls back to.
  static void initBaseline() => _apply(const [], SystemUiMode.edgeToEdge);

  /// Saves the current config and applies [orientations] / [mode].
  static void push({
    required List<DeviceOrientation> orientations,
    required SystemUiMode mode,
  }) {
    _stack.add(_current ?? (const [], SystemUiMode.edgeToEdge));
    _apply(orientations, mode);
  }

  /// Pops the most recent [push]; with an empty stack reapplies the baseline.
  static void restore() {
    final previous = _stack.isNotEmpty ? _stack.removeLast() : null;
    if (previous == null) {
      initBaseline();
    } else {
      _apply(previous.$1, previous.$2);
    }
  }

  static void _apply(List<DeviceOrientation> orientations, SystemUiMode mode) {
    _current = (orientations, mode);
    // ponytail: one global chain serializes platform calls; per-page chains
    // only matter if pages ever render on multiple concurrent views.
    _chain = _chain.then((_) async {
      await SystemChrome.setPreferredOrientations(orientations);
      await SystemChrome.setEnabledSystemUIMode(mode);
    });
  }
}
