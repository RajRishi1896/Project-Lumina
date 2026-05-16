import 'package:flutter/material.dart';
import 'browse_node.dart';
import '../features/dashboard/presentation/dashboard_page.dart' as feat;
import '../shared/services/mock_data_service.dart';
import '../widgets/connection_gate.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  
  final List<Widget> _pages = [
    const feat.DashboardPage(),
    const BrowseNodePage(),
  ];

  @override
  Widget build(BuildContext context) {
    // Check for empty library (offline mode requirement)
    final resources = MockDataService.getResources();
    final hasDownloadedResources = resources.any((r) => r.isDownloaded);

    if (!hasDownloadedResources) {
      return ConnectionGate(
        forceOffline: true,
        child: _buildShell(),
      );
    }

    return _buildShell();
  }

  Widget _buildShell() {
    return Scaffold(
      body: SafeArea(child: _pages[_index]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        selectedItemColor: Theme.of(context).colorScheme.secondary,
        unselectedItemColor: Colors.grey[600],
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.cloud), label: 'Browse'),
        ],
      ),
    );
  }
}
