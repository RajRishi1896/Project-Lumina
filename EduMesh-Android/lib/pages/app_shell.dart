import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:edumesh_android/features/dashboard/presentation/dashboard_page.dart';
import 'package:edumesh_android/core/constants/lumina_colors.dart';
import 'package:edumesh_android/features/dashboard/presentation/saved_resource_page.dart';
import 'package:edumesh_android/features/dashboard/presentation/student_profile_page.dart';
import 'package:edumesh_android/features/dashboard/presentation/search_page.dart';
import 'package:edumesh_android/shared/widgets/mini_player_widget.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';

/// The main application shell with a 4-tab bottom navigation bar.
///
/// Hosts the [DashboardPage], [SearchPage], [SavedResourcesPage],
/// and [StudentProfilePage] in an [IndexedStack]
/// and overlays the [MiniPlayerWidget] on top. Pressing back twice within
/// two seconds exits the app via [SystemNavigator.pop].
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  DateTime? _lastBackPress;

  final List<Widget> _pages = [
    const DashboardPage(),
    const SearchPage(),
    const SavedResourcesPage(),
    const StudentProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_lastBackPress != null && DateTime.now().difference(_lastBackPress!) < const Duration(seconds: 2)) {
          SystemNavigator.pop();
          return;
        }
        _lastBackPress = DateTime.now();
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
            IndexedStack(index: _index, children: _pages),
            const MiniPlayerWidget(),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _index,
          onTap: (val) => setState(() => _index = val),
          type: BottomNavigationBarType.fixed,
          selectedItemColor: LuminaColors.academicTeal,
          unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant,
          items: [
            BottomNavigationBarItem(icon: const Icon(Icons.dashboard_rounded), label: AppLocalizations.of(context)!.bottomNavDashboard),
            BottomNavigationBarItem(icon: const Icon(Icons.explore_rounded), label: AppLocalizations.of(context)!.bottomNavBrowse),
            BottomNavigationBarItem(icon: const Icon(Icons.bookmark_rounded), label: AppLocalizations.of(context)!.bottomNavSaved),
            BottomNavigationBarItem(icon: const Icon(Icons.person_rounded), label: AppLocalizations.of(context)!.bottomNavProfile),
          ],
        ),
      ),
    );
  }
}
