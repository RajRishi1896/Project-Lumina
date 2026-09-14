import 'package:flutter/material.dart';
import 'package:flutter/services.dart';import 'package:edumesh_android/core/navigation/lumina_transitions.dart';
import 'package:edumesh_android/core/services/activity_tracker.dart';
import 'package:edumesh_android/features/dashboard/presentation/dashboard_page.dart';
import 'package:edumesh_android/features/dashboard/presentation/saved_resource_page.dart';
import 'package:edumesh_android/features/dashboard/presentation/student_profile_page.dart';
import 'package:edumesh_android/features/dashboard/presentation/browse_page.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';
import 'package:edumesh_android/shared/widgets/mini_player_widget.dart';

/// The main application shell with a 4-tab bottom navigation bar.
///
/// Hosts the [DashboardPage], [BrowsePage], [SavedResourcesPage],
/// and [StudentProfilePage] in an [IndexedStack].
/// Pressing back twice within two seconds exits the app via [SystemNavigator.pop].
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int _index = 0;
  final _browseKey = GlobalKey<BrowsePageState>();

  /// Subtle fade when switching tabs; skipped entirely when animations are
  /// off or reduced motion is on (the IndexedStack swap is already instant).
  late final AnimationController _tabFade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 100),
    value: 1,
  );

  void _selectTab(int index) {
    if (index == _index) return;
    setState(() => _index = index);
    if (LuminaTransitions.enabled(context)) {
      _tabFade.forward(from: 0);
    } else {
      _tabFade.value = 1;
    }
    if (index == 2) SavedResourcesPage.refreshNotifier.value++;
  }

  void _openBrowseResources() {
    _selectTab(1);
    _browseKey.currentState?.switchTab(1);
  }

  late final List<Widget> _pages = [
    DashboardPage(onBrowseTap: _openBrowseResources),
    BrowsePage(key: _browseKey),
    const SavedResourcesPage(),
    const StudentProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabFade.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ActivityTracker().onLifecycleChange(state);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // No double-press gate: a single back press only shows the toast;
      // leaving happens exclusively through its Exit action. This keeps
      // every flow (tabs, sheets, pushed pages) at an explicit step.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final messenger = ScaffoldMessenger.of(context);
        final l10n = AppLocalizations.of(context)!;
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.doubleBackToExitMessage),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            action: SnackBarAction(label: l10n.exitButtonLabel, onPressed: () => SystemNavigator.pop()),
          ),
        );
      },
      child: Scaffold(
        body: Stack(
          children: [
            FadeTransition(
              opacity: _tabFade,
              child: IndexedStack(index: _index, children: _pages),
            ),
            const MiniPlayerWidget(),
          ],
        ),
        bottomNavigationBar: Builder(
          builder: (context) {
            final cs = Theme.of(context).colorScheme;
            return Theme(
              data: Theme.of(context).copyWith(
                splashColor: cs.primary.withValues(alpha: 0.08),
                highlightColor: cs.primary.withValues(alpha: 0.04),
              ),
              child: BottomNavigationBar(
                type: BottomNavigationBarType.fixed,
                currentIndex: _index,
                onTap: _selectTab,
                items: [
                  BottomNavigationBarItem(icon: const Icon(Icons.dashboard_rounded), label: AppLocalizations.of(context)!.bottomNavDashboard),
                  BottomNavigationBarItem(icon: const Icon(Icons.explore_rounded), label: AppLocalizations.of(context)!.bottomNavBrowse),
                  BottomNavigationBarItem(icon: const Icon(Icons.bookmark_rounded), label: AppLocalizations.of(context)!.bottomNavSaved),
                  BottomNavigationBarItem(icon: const Icon(Icons.person_rounded), label: AppLocalizations.of(context)!.bottomNavProfile),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
