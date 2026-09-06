import 'dart:async';

import 'package:flutter/material.dart';

import '../providers/animation_prefs.dart';

/// Central animation gate + transition builders for the whole app.
///
/// Every supported animation funnels through [enabled] so the settings
/// toggle and the platform reduced-motion flag are honoured in one place.
/// Durations stay in the ~100 ms band; nothing here loops or chains.
class LuminaTransitions {
  LuminaTransitions._();

  /// Standard transition length when animations are enabled.
  static const Duration duration = Duration(milliseconds: 100);

  /// Whether transitions should run at this [context]: the user setting must
  /// be ON and the platform reduced-motion flag must be OFF.
  static bool enabled(BuildContext context) =>
      AnimationPrefs().enabled && !MediaQuery.disableAnimationsOf(context);

  /// Context-free variant of [enabled] for route constructors, reading the
  /// platform reduced-motion flag straight from the dispatcher.
  static bool get globalEnabled =>
      AnimationPrefs().enabled &&
      !WidgetsBinding
          .instance.platformDispatcher.accessibilityFeatures.disableAnimations;
}

/// The app's standard page route: slide + fade when animations are on, an
/// instant swap when the setting is off or reduced motion applies.
/// Drop-in for `MaterialPageRoute`.
PageRoute<T> luminaRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
  bool fullscreenDialog = false,
}) {
  final animate = LuminaTransitions.globalEnabled;
  return PageRouteBuilder<T>(
    settings: settings,
    fullscreenDialog: fullscreenDialog,
    transitionDuration: animate ? LuminaTransitions.duration : Duration.zero,
    reverseTransitionDuration:
        animate ? LuminaTransitions.duration : Duration.zero,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (!animate) return child;
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.06, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Shows a non-dismissible loading spinner while [future] completes, then
/// hides it and returns (or rethrows) its result.
///
/// Wrap network fetches that run between a tap and pushing a viewer (Kiwix
/// article fetch, PDF staleness re-download) so the tap gets visible
/// feedback within 300ms. Only wrap the network call itself: cache hits
/// stay instant with no spinner flash.
Future<T> fetchWithLoading<T>(BuildContext context, Future<T> future) async {
  // showGeneralDialog uses the root navigator by default; pop the same one.
  final nav = Navigator.of(context, rootNavigator: true);
  unawaited(showGeneralDialog(
    context: context,
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    pageBuilder: (_, __, ___) => const PopScope(
      canPop: false,
      child: Center(child: CircularProgressIndicator()),
    ),
  ));
  try {
    return await future;
  } finally {
    try {
      nav.pop();
    } catch (_) {}
  }
}

/// Shows a dialog with a lightweight fade+scale when animations are on and
/// an instant appearance when off/reduced. Drop-in for `showDialog`: the
/// [builder] content is wrapped in a [Dialog] exactly like the original.
Future<T?> showLuminaDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
  String? barrierLabel,
  ShapeBorder? shape,
}) {
  final animate = LuminaTransitions.enabled(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel ??
        MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: animate ? LuminaTransitions.duration : Duration.zero,
    barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.54),
    pageBuilder: (context, animation, secondaryAnimation) =>
        Dialog(shape: shape, child: builder(context)),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      if (!animate) return child;
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Shows a bottom sheet with the standard slide-up when animations are on
/// and an instant appearance when off/reduced. The [builder] content is
/// bottom-anchored and keyboard-aware, matching `showModalBottomSheet`.
Future<T?> showLuminaSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = true,
  ShapeBorder? shape,
}) {
  final animate = LuminaTransitions.enabled(context);
  final sheet = Builder(
    builder: (context) {
      Widget content = Material(
        color: Theme.of(context).bottomSheetTheme.backgroundColor ??
            Theme.of(context).colorScheme.surface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: builder(context),
      );
      // Mirror showModalBottomSheet's default half-screen cap.
      if (!isScrollControlled) {
        content = ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 9 / 16),
          child: content,
        );
      }
      return content;
    },
  );
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.54),
    transitionDuration: animate ? LuminaTransitions.duration : Duration.zero,
    pageBuilder: (context, animation, secondaryAnimation) => sheet,
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final anchored = Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(bottom: false, top: !useSafeArea, child: child),
      );
      if (!animate) return anchored;
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
            .animate(curved),
        child: FadeTransition(opacity: curved, child: anchored),
      );
    },
  );
}
