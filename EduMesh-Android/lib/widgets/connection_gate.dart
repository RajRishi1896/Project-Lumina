import 'package:flutter/material.dart';

/// A widget that conditionally wraps its child for offline-aware rendering.
///
/// Currently acts as a pass-through that always shows [child]. In future
/// versions this gate may block UI or show a warning when the device has
/// no connectivity (controlled by [forceOffline]).
class ConnectionGate extends StatelessWidget {
  /// The child widget to render inside the gate.
  final Widget child;

  /// Whether to simulate offline mode regardless of actual connectivity.
  ///
  /// When `true`, the gate may restrict certain online-only features.
  final bool forceOffline;

  const ConnectionGate({
    super.key,
    required this.child,
    this.forceOffline = false,
  });

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
