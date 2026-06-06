import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:edumesh_android/features/dashboard/presentation/dashboard_page.dart' as feat;
import 'package:edumesh_android/core/constants/lumina_colors.dart';
import 'package:edumesh_android/features/dashboard/presentation/saved_resource_page.dart';
import 'package:edumesh_android/features/dashboard/presentation/student_profile_page.dart';
import 'package:edumesh_android/features/dashboard/presentation/search_page.dart';
import 'package:edumesh_android/features/teacher/presentation/teacher_monitor_page.dart';
import 'package:edumesh_android/shared/widgets/mini_player_widget.dart';

/// The main application shell with a 5-tab bottom navigation bar.
///
/// Hosts the [DashboardPage], [SearchPage], [SavedResourcesPage],
/// [StudentProfilePage], and [TeacherMonitorPage] in an [IndexedStack]
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
    const feat.DashboardPage(),
    const SearchPage(),
    const SavedResourcesPage(),
    const StudentProfilePage(),
    const TeacherMonitorPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return _buildShell();
  }

  Widget _buildShell() {
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
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Press back again to exit'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            action: SnackBarAction(label: 'Exit', onPressed: () => SystemNavigator.pop()),
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
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Dashboard'),
            BottomNavigationBarItem(icon: Icon(Icons.explore_rounded), label: 'Browse'),
            BottomNavigationBarItem(icon: Icon(Icons.bookmark_rounded), label: 'Saved'),
            BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Profile'),
            BottomNavigationBarItem(icon: Icon(Icons.supervisor_account_rounded), label: 'Students'),
          ],
        ),
      ),
    );
  }
}
