import 'dart:async';
import 'package:edumesh_android/core/navigation/lumina_transitions.dart';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../pages/app_shell.dart';
import '../../../widgets/connection_gate.dart';

/// One-time introductory tour shown after the first successful login.
///
/// Four static slides presented in a swipeable [PageView] with a dot
/// indicator. Completing the last slide or tapping Skip persists
/// [AppTourPage.seenPrefKey] so the tour never shows again.
class AppTourPage extends StatefulWidget {
  /// SharedPreferences flag set to true once the tour is completed or skipped.
  static const String seenPrefKey = 'tour_seen_v1';

  /// Called instead of navigating to [AppShell] when provided.
  ///
  /// Used by [FirstRunTourGate], which reveals its own child rather than
  /// routing directly to the shell.
  final VoidCallback? onFinished;

  const AppTourPage({super.key, this.onFinished});

  @override
  State<AppTourPage> createState() => _AppTourPageState();
}

class _AppTourPageState extends State<AppTourPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Builds the slide contents. Strings resolve through [AppLocalizations]
  /// so each slide renders in the student's selected language.
  List<_TourSlideData> _slides(AppLocalizations l10n) => [
        _TourSlideData(Icons.school_outlined, l10n.tourTitleWelcome, l10n.tourBodyWelcome),
        _TourSlideData(Icons.download_outlined, l10n.tourTitleOffline, l10n.tourBodyOffline),
        _TourSlideData(Icons.account_circle_outlined, l10n.tourTitleProgress, l10n.tourBodyProgress),
        _TourSlideData(Icons.language, l10n.tourTitleLanguage, l10n.tourBodyLanguage),
      ];

  /// Persists the seen flag, then either hands control back to
  /// [widget.onFinished] or routes to the app shell.
  Future<void> _complete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppTourPage.seenPrefKey, true);
    if (!mounted) return;
    if (widget.onFinished != null) {
      widget.onFinished!();
      return;
    }
    unawaited(Navigator.of(context).pushReplacement(
      luminaRoute(
        builder: (_) => const ConnectionGate(child: AppShell()),
      ),
    ));
  }

  /// Advances to the next slide, or completes the tour from the last one.
  void _goNext() {
    final slides = _slides(AppLocalizations.of(context)!);
    if (_currentPage >= slides.length - 1) {
      unawaited(_complete());
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    final slides = _slides(l10n);
    final isLast = _currentPage >= slides.length - 1;

    final scaffold = Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _complete,
                  style: TextButton.styleFrom(
                    minimumSize: Size(AppSpacing.touchTarget.w, AppSpacing.touchTarget.h),
                  ),
                  child: Text(l10n.tourSkip),
                ),
                SizedBox(width: AppSpacing.sm.w),
              ],
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) => setState(() => _currentPage = index),
                children: slides.map((slide) => _buildSlide(slide, cs, tt)).toList(),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(
                left: AppSpacing.xxl.w,
                right: AppSpacing.xxl.w,
                bottom: AppSpacing.xl.h,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < slides.length; i++) _buildDot(i, cs),
                      ],
                    ),
                  ),
                  SizedBox(height: AppSpacing.lg.h),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _goNext,
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size.fromHeight(AppSpacing.touchTarget.h),
                      ),
                      child: Text(isLast ? l10n.tourGetStarted : l10n.tourNext),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    // System back must count as Skip: otherwise the seen flag is never set
    // and the tour replays on every launch for back-button users.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) => unawaited(_complete()),
      child: scaffold,
    );
  }

  /// Builds one full-screen slide: tinted icon circle, title, and body.
  Widget _buildSlide(_TourSlideData slide, ColorScheme cs, TextTheme tt) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.xxl.w),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96.w,
            height: 96.w,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(slide.icon, size: 48.sp, color: cs.primary),
          ),
          SizedBox(height: AppSpacing.section.h),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: tt.headlineSmall?.copyWith(color: cs.primary),
          ),
          SizedBox(height: AppSpacing.md.h),
          Text(
            slide.body,
            textAlign: TextAlign.center,
            style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// Builds the page-indicator dot for [index]; the active dot is wider.
  Widget _buildDot(int index, ColorScheme cs) {
    final isActive = index == _currentPage;
    return Container(
      width: (isActive ? AppSpacing.lg : AppSpacing.sm).w,
      height: AppSpacing.sm.h,
      margin: EdgeInsets.symmetric(horizontal: AppSpacing.xs.w),
      decoration: BoxDecoration(
        color: isActive ? cs.primary : cs.outlineVariant,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull.r),
      ),
    );
  }
}

/// Immutable content for a single tour slide.
class _TourSlideData {
  final IconData icon;
  final String title;
  final String body;

  const _TourSlideData(this.icon, this.title, this.body);
}

/// Shows [AppTourPage] before [child] until the tour has been seen once.
///
/// Used on the registration path, where [ProfileSetupPage] routes itself to
/// the shell and cannot be intercepted externally. While preferences load, a
/// blank scaffold renders to avoid flashing the child behind the tour.
class FirstRunTourGate extends StatefulWidget {
  /// The page revealed once the tour is completed or skipped.
  final Widget child;

  const FirstRunTourGate({super.key, required this.child});

  @override
  State<FirstRunTourGate> createState() => _FirstRunTourGateState();
}

class _FirstRunTourGateState extends State<FirstRunTourGate> {
  bool? _seen;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSeen());
  }

  Future<void> _loadSeen() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _seen = prefs.getBool(AppTourPage.seenPrefKey) ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final seen = _seen;
    if (seen == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
      );
    }
    if (seen) return widget.child;
    return AppTourPage(
      onFinished: () {
        if (mounted) setState(() => _seen = true);
      },
    );
  }
}
