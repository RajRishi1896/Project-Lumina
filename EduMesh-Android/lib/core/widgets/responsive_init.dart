import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Recomputes the clamped design size on EVERY metrics change and feeds it to
/// ScreenUtil via its public [ScreenUtil.configure], so `.w/.h/.sp` stay
/// correct in any orientation on any device.
///
/// Replaces `ScreenUtilInit`: that package's `designSize` is a frozen widget
/// field computed by the parent, so a tablet launched in landscape keeps
/// dividing portrait pixels by landscape units (0.625 width / 1.6 height
/// scales). Here the clamp and the metrics observer live in the same widget,
/// so they can never disagree.
class ResponsiveInit extends StatefulWidget {
  /// Builds the app below the configured [ScreenUtil].
  const ResponsiveInit({super.key, required this.builder});

  /// Called on every build with the freshly configured scope.
  final WidgetBuilder builder;

  @override
  State<ResponsiveInit> createState() => _ResponsiveInitState();
}

class _ResponsiveInitState extends State<ResponsiveInit>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() => setState(() {});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = View.of(context);
    final metrics = MediaQueryData.fromView(view);
    // Fixed phone baseline (360×780) so .w/.h/.sp scale UP on tablets.
    // ScreenUtil multiplies by (screenSize / designSize), so a 800dp-wide
    // tablet gets 2.2× scale — elements fill the screen proportionally
    // instead of rendering at phone pixel sizes on a bigger canvas.
    const design = Size(360.0, 780.0);
    ScreenUtil.configure(
      data: metrics,
      designSize: design,
      minTextAdapt: true,
      splitScreenMode: true,
    );
    return widget.builder(context);
  }
}
