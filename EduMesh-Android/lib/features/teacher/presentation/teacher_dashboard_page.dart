import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../auth/data/auth_service.dart';
import '../data/teacher_repository.dart';
import 'tabs/content_manager_tab.dart';
import 'tabs/security_tab.dart';
import 'tabs/danger_zone_tab.dart';
import 'tabs/settings_tab.dart';

class TeacherDashboardPage extends StatefulWidget {
  const TeacherDashboardPage({super.key});

  @override
  State<TeacherDashboardPage> createState() => _TeacherDashboardPageState();
}

class _TeacherDashboardPageState extends State<TeacherDashboardPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final bool _isAdmin = AuthService.isAdmin();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _isAdmin ? 4 : 2, vsync: this);
    TeacherRepository.init();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text('Teacher Dashboard',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18.sp)),
            if (AuthService.isDemoMode) ...[
              SizedBox(width: 8.w),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('Demo',
                    style: TextStyle(
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w600,
                        color: cs.primary)),
              ),
            ],
          ],
        ),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: cs.primary,
          unselectedLabelColor: cs.onSurfaceVariant,
          indicatorColor: cs.primary,
          tabs: [
            const Tab(text: 'Content Manager'),
            const Tab(text: 'Security'),
            if (_isAdmin) const Tab(text: 'Danger Zone'),
            if (_isAdmin) const Tab(text: 'Settings'),
          ],
        ),
      ),
      backgroundColor: cs.surface,
      body: TabBarView(
        controller: _tabController,
        children: [
          const ContentManagerTab(),
          const SecurityTab(),
          if (_isAdmin) const DangerZoneTab(),
          if (_isAdmin) const SettingsTab(),
        ],
      ),
    );
  }
}
