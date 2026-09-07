import 'package:flutter/services.dart';

/// Thin wrapper around the native Android PiP method channel.
class PiPHelper {
  PiPHelper._();
  static final PiPHelper instance = PiPHelper._();
  factory PiPHelper() => instance;

  static const _channel = MethodChannel('com.edumesh.android/pip');

  bool _supported = false;
  bool _inPiP = false;
  bool _listening = false;
  Future<void>? _initializing;

  /// Whether PiP mode is currently active.
  bool get isInPiP => _inPiP;

  /// Whether the device supports PiP (Android 8.0+).
  bool get isSupported => _supported;

  /// Callback fired when PiP mode changes. Set by the video player page.
  void Function(bool isInPiP)? onModeChanged;

  /// Callback fired when a PiP action button is tapped (play_pause, forward).
  void Function(String action)? onAction;

  /// Initialize: check support and start listening for mode changes.
  ///
  /// Initialization is shared so a user can tap PiP immediately after the
  /// player opens without racing the capability check.
  Future<void> init() async {
    if (_initializing != null) {
      await _initializing;
      return;
    }
    final future = _initialize();
    _initializing = future;
    try {
      await future;
    } finally {
      _initializing = null;
    }
  }

  Future<void> _initialize() async {
    try {
      _supported = await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      _supported = false;
    }
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler(_handleCallback);
    }
  }

  Future<void> _handleCallback(MethodCall call) async {
    switch (call.method) {
      case 'onPiPModeChanged':
        _inPiP = call.arguments as bool;
        onModeChanged?.call(_inPiP);
        break;
      case 'onPiPAction':
        final action = call.arguments as String;
        onAction?.call(action);
        break;
    }
  }

  /// Enter PiP mode. Returns true if the system entered PiP.
  Future<bool> enterPiP({
    int width = 16,
    int height = 9,
    bool isPlaying = true,
  }) async {
    await init();
    if (!_supported) return false;
    try {
      final result = await _channel.invokeMethod<bool>(
        'enterPiP',
        {'width': width, 'height': height, 'isPlaying': isPlaying},
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Update the PiP overlay actions (e.g. toggle play/pause icon).
  Future<void> updatePiPActions({
    int width = 16,
    int height = 9,
    bool isPlaying = true,
  }) async {
    await init();
    if (!_supported) return;
    try {
      await _channel.invokeMethod(
        'updatePiPActions',
        {'width': width, 'height': height, 'isPlaying': isPlaying},
      );
    } catch (_) {}
  }

  /// Exit PiP mode. Android leaves PiP through the normal system expansion
  /// flow; this channel remains as a compatibility hook for the platform.
  Future<void> exitPiP() async {
    await init();
    if (!_supported) return;
    try {
      await _channel.invokeMethod('exitPiP');
    } catch (_) {}
  }
}
