import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:app_settings/app_settings.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../features/auth/data/auth_service.dart';
import '../../../features/auth/presentation/welcome_page.dart';
import '../../../features/teacher/presentation/teacher_dashboard_page.dart';
import '../../../shared/services/mock_data_service.dart';

class LuminaSettingsSheet extends ConsumerWidget {
  final VoidCallback? onManageStorage;

  const LuminaSettingsSheet({super.key, this.onManageStorage});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Universal Settings',
              style: TextStyle(
                fontSize: 22.sp,
                fontWeight: FontWeight.w800,
                color: cs.primary,
              ),
            ),
            SizedBox(height: 20.h),
            
            // Theme Toggle
            SwitchListTile(
              title: const Text('Dark Mode'),
              subtitle: const Text('Switch to high-contrast dark theme'),
              secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode, color: cs.primary),
              value: isDark,
              onChanged: (_) => ref.read(themeModeProvider.notifier).toggle(),
            ),
            
            // Profile
            ListTile(
              leading: Icon(Icons.person, color: cs.primary),
              title: const Text('Scholar Profile'),
              subtitle: const Text('Manage your identity and badges'),
              onTap: () => Navigator.pop(context),
            ),
            
            // Storage
            ListTile(
              leading: Icon(Icons.storage, color: cs.primary),
              title: const Text('Storage & Offline Library'),
              subtitle: const Text('Manage downloaded content'),
              onTap: () {
                Navigator.pop(context);
                if (onManageStorage != null) {
                  onManageStorage!();
                }
              },
            ),
            
            // Teacher Dashboard (admin only)
            if (AuthService.isAdmin())
              ListTile(
                leading: Icon(Icons.admin_panel_settings, color: cs.primary),
                title: const Text('Teacher Dashboard'),
                subtitle: const Text('Manage content, users, and settings'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TeacherDashboardPage()),
                  );
                },
              ),

            // Demo Mode Controls (visible only when demo mode is on)
            if (AuthService.isDemoMode) ...[
              const Divider(),
              Padding(
                padding: EdgeInsets.only(left: 16.w, top: 8.h, bottom: 4.h),
                child: Row(
                  children: [
                    Icon(Icons.science_rounded, size: 18.sp, color: cs.primary),
                    SizedBox(width: 8.w),
                    Text('Demo Mode',
                        style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w700,
                            color: cs.primary)),
                  ],
                ),
              ),
              SwitchListTile(
                secondary: Icon(
                    AuthService.isDemoAdmin() ? Icons.admin_panel_settings : Icons.person,
                    color: cs.primary),
                title: Text(AuthService.isDemoAdmin() ? 'Admin View' : 'Student View'),
                subtitle: Text(AuthService.isDemoAdmin()
                    ? 'Full access to all features'
                    : 'Limited student experience'),
                value: AuthService.isDemoAdmin(),
                onChanged: (val) {
                  AuthService.setDemoAdminRole(val);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(val
                        ? 'Switched to Admin view'
                        : 'Switched to Student view'),
                    duration: const Duration(seconds: 1),
                  ));
                },
              ),
              ListTile(
                leading: Icon(Icons.refresh, color: cs.primary),
                title: const Text('Reset Demo Content'),
                subtitle: const Text('Re-seed sample resources'),
                onTap: () {
                  MockDataService.initializeWithDummyData();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Demo content reset'), duration: Duration(seconds: 1)),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.info_outline, color: cs.primary),
                title: const Text('About Demo Mode'),
                subtitle: const Text('Learn what demo mode offers'),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Row(
                        children: [
                          Icon(Icons.science_rounded, color: cs.primary),
                          SizedBox(width: 8.w),
                          const Text('Demo Mode'),
                        ],
                      ),
                      content: const Text(
                        'EduMesh Demo Mode provides a sandboxed environment to explore all app features without requiring a live server connection.\n\n'
                        'What you can do:\n'
                        '• Toggle between Admin and Student roles\n'
                        '• Load sample data into the Teacher Dashboard\n'
                        '• Explore Content Manager, Security, Danger Zone, and Settings tabs\n'
                        '• Reset demo content anytime\n\n'
                        'To disable demo mode, set isDemoMode = false in auth_service.dart and rebuild.',
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it')),
                      ],
                    ),
                  );
                },
              ),
            ],

            // Network
            ListTile(
              leading: Icon(Icons.wifi, color: cs.primary),
              title: const Text('Network Settings'),
              subtitle: const Text('Configure Hub connectivity'),
              onTap: () {
                Navigator.pop(context);
                AppSettings.openAppSettings(type: AppSettingsType.wifi);
              },
            ),
            
            const Divider(),
            
            // Logout
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text('Log Out', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              onTap: () async {
                await AuthService().logout();
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const WelcomePage()),
                    (route) => false,
                  );
                }
              },
            ),
            SizedBox(height: 8.h),
          ],
        ),
      ),
    );
  }
}
