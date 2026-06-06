import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:app_settings/app_settings.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../features/auth/data/auth_service.dart';
import '../../../features/auth/presentation/welcome_page.dart';
import '../../../shared/widgets/offline_library_page.dart';

/// A bottom-sheet settings panel displayed inside the app.
///
/// Contains a dark-mode toggle, navigation to the offline library and
/// network settings, and a log-out action that returns the user to the
/// [WelcomePage].
class LuminaSettingsSheet extends ConsumerWidget {
  const LuminaSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.only(top: AppSpacing.sm.h),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusXl.r)),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.only(bottom: AppSpacing.section.h),
        children: [
          Center(
            child: Container(
              width: AppSpacing.sectionLg.w,
              height: AppSpacing.xs.h,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
            ),
          ),
          SizedBox(height: AppSpacing.lg.h),

          Padding(
            padding: EdgeInsets.only(left: AppSpacing.lg.w, bottom: AppSpacing.sm.h),
            child: Text('Settings',
                style: TextStyle(
                    fontSize: 20.sp,
                    fontWeight: AppSpacing.weightDisplay,
                    color: cs.onSurface)),
          ),

          // Theme toggle
          Consumer(builder: (context, ref, child) {
            final themeMode = ref.watch(themeModeProvider);
            final isDark = themeMode == ThemeMode.dark;
            return SwitchListTile(
              secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode, color: cs.primary),
              title: Text(isDark ? 'Dark Mode' : 'Light Mode'),
              subtitle: Text(isDark ? 'Switch to light theme' : 'Switch to dark theme'),
              value: isDark,
              onChanged: (val) {
                ref.read(themeModeProvider.notifier).setMode(val ? ThemeMode.dark : ThemeMode.light);
              },
            );
          }),

          // Storage
          ListTile(
            leading: Icon(Icons.storage, color: cs.primary),
            title: const Text('Storage & Offline Library'),
            subtitle: const Text('Manage downloaded content'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const OfflineLibraryPage()));
            },
          ),

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

          ListTile(
            leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
            title: Text('Log Out', style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: AppSpacing.weightStrong)),
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
    );
  }
}
