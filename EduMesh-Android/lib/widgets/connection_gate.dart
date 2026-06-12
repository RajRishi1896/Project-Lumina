import 'package:flutter/material.dart';
import '../shared/services/connectivity_service.dart';
import '../core/constants/app_spacing.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';

/// Wraps [child] and shows a non-blocking offline banner at the top when
/// the device has no connectivity to the hub. The child is always rendered
/// so offline usage is not blocked.
class ConnectionGate extends StatefulWidget {
  final Widget child;
  const ConnectionGate({required this.child, super.key});

  @override
  State<ConnectionGate> createState() => _ConnectionGateState();
}

class _ConnectionGateState extends State<ConnectionGate> {
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _isOffline = !ConnectivityService().isOnline;
    ConnectivityService().addListener(_onConnectivityChange);
  }

  void _onConnectivityChange() {
    if (!mounted) return;
    setState(() {
      _isOffline = !ConnectivityService().isOnline;
    });
  }

  @override
  void dispose() {
    ConnectivityService().removeListener(_onConnectivityChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      children: [
        if (_isOffline)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs, horizontal: AppSpacing.lg),
            color: cs.error,
            child: Text(
              AppLocalizations.of(context)!.connectionOfflineBanner,
              style: tt.bodySmall?.copyWith(color: cs.onError),
            ),
          ),
        Expanded(child: widget.child),
      ],
    );
  }
}
