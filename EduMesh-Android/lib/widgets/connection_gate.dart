import 'dart:async';
import 'package:flutter/material.dart';
import '../shared/services/connectivity_service.dart';
import '../core/constants/app_spacing.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';

/// Wraps [child] and shows a temporary overlay banner when the device loses
/// hub connectivity. The banner auto-dismisses after 7 seconds or can be
/// dismissed manually via the X button. The child is always rendered so
/// offline usage is not blocked.
class ConnectionGate extends StatefulWidget {
  /// The widget rendered beneath the offline banner.
  final Widget child;
  const ConnectionGate({required this.child, super.key});

  @override
  State<ConnectionGate> createState() => _ConnectionGateState();
}

class _ConnectionGateState extends State<ConnectionGate> {
  OverlayEntry? _overlayEntry;
  Timer? _dismissTimer;
  bool _wasOffline = false;

  @override
  void initState() {
    super.initState();
    _wasOffline = !ConnectivityService().isOnline;
    ConnectivityService().addListener(_onConnectivityChange);
  }

  void _onConnectivityChange() {
    if (!mounted) return;
    final isOffline = !ConnectivityService().isOnline;
    if (isOffline && !_wasOffline) {
      _showBanner();
    }
    _wasOffline = isOffline;
  }

  void _showBanner() {
    _dismissTimer?.cancel();
    _overlayEntry?.remove();
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
    _dismissTimer = Timer(const Duration(seconds: 7), _dismissBanner);
  }

  void _dismissBanner() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  OverlayEntry _createOverlayEntry() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    return OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + AppSpacing.xs,
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            decoration: BoxDecoration(
              color: cs.error,
              borderRadius: BorderRadius.circular(AppSpacing.md),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.connectionOfflineBanner,
                    style: tt.bodyLarge?.copyWith(color: cs.onError),
                  ),
                ),
                GestureDetector(
                  onTap: _dismissBanner,
                  child: Icon(Icons.close, color: cs.onError, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _overlayEntry?.remove();
    ConnectivityService().removeListener(_onConnectivityChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
