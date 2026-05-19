import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'browse_node.dart';
import 'teacher_upload_panel.dart';
import '../features/dashboard/presentation/dashboard_page.dart' as feat;
import '../shared/services/mock_data_service.dart';
import '../widgets/connection_gate.dart';
import '../features/auth/data/auth_service.dart';
import '../shared/widgets/lumina_settings_sheet.dart';
import '../shared/widgets/lumina_card.dart';
import '../core/constants/lumina_colors.dart';

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
    const _SavedResourcesView(),
    const _ScholarProfileView(),
  ];

  @override
  Widget build(BuildContext context) {
    // Check for empty library (offline mode requirement)
    final resources = MockDataService.getResources();
    final hasDownloadedResources = resources.any((r) => r.isDownloaded);

    if (!hasDownloadedResources && !AuthService.isDemoMode) {
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
        type: BottomNavigationBarType.fixed,
        selectedItemColor: LuminaColors.academicTeal,
        unselectedItemColor: Colors.grey[400],
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.sp),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.normal, fontSize: 10.sp),
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Portal'),
          BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: 'Subjects'),
          BottomNavigationBarItem(icon: Icon(Icons.download_for_offline), label: 'Saved'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

class _SavedResourcesView extends StatelessWidget {
  const _SavedResourcesView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('SAVED RESOURCES', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w800, color: LuminaColors.onSurface, letterSpacing: 1.0)),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_off_outlined, size: 64.sp, color: Colors.grey.shade300),
            SizedBox(height: 16.h),
            Text('There is nothing here', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600, fontSize: 14.sp)),
          ],
        ),
      ),
    );
  }
}

class _ScholarProfileView extends StatelessWidget {
  const _ScholarProfileView();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text('SCHOLAR PROFILE', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w800, color: LuminaColors.onSurface, letterSpacing: 1.0)),
        backgroundColor: cs.surface,
        elevation: 0,
      ),
      body: ListView(
        padding: EdgeInsets.all(24.w),
        children: [
          Center(
            child: CircleAvatar(
              radius: 48.r,
              backgroundColor: LuminaColors.academicTeal.withOpacity(0.1),
              child: Icon(Icons.person, size: 48.sp, color: LuminaColors.academicTeal),
            ),
          ),
          SizedBox(height: 16.h),
          Center(
            child: Text(
              AuthService.isDemoMode ? AuthService.demoUsername.toUpperCase() : 'SCHOLAR',
              style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w800, color: cs.primary),
            ),
          ),
          SizedBox(height: 4.h),
          Center(
            child: Text(
              AuthService.isDemoMode ? AuthService.demoUserId : 'ID: LUMINA-SCHOLAR',
              style: TextStyle(fontSize: 12.sp, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(height: 32.h),
          LuminaCard(
            padding: EdgeInsets.all(16.w),
            borderColor: cs.outlineVariant,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.verified_user, color: LuminaColors.academicTeal),
                  title: Text('Demo Mode Active', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp)),
                  subtitle: Text('Offline simulation enabled', style: TextStyle(fontSize: 12.sp)),
                  trailing: const Icon(Icons.check_circle, color: LuminaColors.successGreen),
                ),
                Divider(height: 1, color: cs.outlineVariant),
                ListTile(
                  leading: Icon(Icons.settings, color: cs.primary),
                  title: Text('App Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp)),
                  subtitle: Text('Manage storage and theme', style: TextStyle(fontSize: 12.sp)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
                      builder: (_) => const LuminaSettingsSheet(),
                    );
                  },
                ),
                Divider(height: 1, color: cs.outlineVariant),
                ListTile(
                  leading: const Icon(Icons.upload_file, color: LuminaColors.academicTeal),
                  title: Text('Teacher Upload Panel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp)),
                  subtitle: Text('Manage Hub resources (Educators only)', style: TextStyle(fontSize: 12.sp)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final isT = await AuthService().isTeacher();
                    if (!isT) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Access Denied: Only teachers connected to the Hub can access this panel.')),
                        );
                      }
                      return;
                    }
                    if (context.mounted) {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ConnectionGate(child: TeacherUploadPanel())),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
