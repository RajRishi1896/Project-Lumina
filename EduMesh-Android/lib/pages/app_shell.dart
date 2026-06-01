import 'package:flutter/material.dart';
import 'package:edumesh_android/features/dashboard/presentation/dashboard_page.dart' as feat;
import 'package:edumesh_android/features/auth/data/auth_service.dart';
import 'package:edumesh_android/core/constants/lumina_colors.dart';
import 'package:edumesh_android/shared/services/mock_data_service.dart';
import 'package:edumesh_android/widgets/connection_gate.dart';
// Import your new file here
// Change this line in app_shell.dart:
import 'package:edumesh_android/features/dashboard/presentation/saved_resource_page.dart';
import 'package:edumesh_android/features/dashboard/presentation/student_profile_page.dart';


class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  // Now _pages is clean and readable
  final List<Widget> _pages = [
    const feat.DashboardPage(),
    const Center(child: Text('Browse Learning Directory')), 
    const SavedResourcesPage(), 
    const StudentProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    final resources = MockDataService.getResources();
    final hasDownloadedResources = resources.any((r) => r.isDownloaded);

    return (!hasDownloadedResources && !AuthService.isDemoMode)
        ? ConnectionGate(forceOffline: true, child: _buildShell())
        : _buildShell();
  }

  Widget _buildShell() {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (val) => setState(() => _index = val),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: LuminaColors.academicTeal,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.explore_rounded), label: 'Browse'),
          BottomNavigationBarItem(icon: Icon(Icons.bookmark_rounded), label: 'Saved'),
          BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Profile'),
        ],
      ),
    );
  }
}