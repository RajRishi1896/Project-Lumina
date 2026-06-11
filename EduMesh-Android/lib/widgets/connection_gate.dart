import 'package:flutter/material.dart';

/// A no-op wrapper widget reserved for future offline-awareness logic.
///
/// Currently renders [child] directly. Intended to conditionally block or
/// warn when the device has no connectivity to the hub.
class ConnectionGate extends StatelessWidget {
  /// The child widget to render.
  final Widget child;

  const ConnectionGate({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => child;
}
