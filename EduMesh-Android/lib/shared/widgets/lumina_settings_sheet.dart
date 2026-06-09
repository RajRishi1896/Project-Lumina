import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:app_settings/app_settings.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/services/connectivity_service.dart';
import '../../../features/auth/data/auth_service.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';
import '../../../features/auth/presentation/welcome_page.dart';
import '../../../shared/widgets/offline_library_page.dart';

/// A bottom-sheet settings panel displayed inside the app.
///
/// Contains a dark-mode toggle, navigation to the offline library,
/// network settings, language selection, account settings with password
/// change, and a log-out action that returns the user to the [WelcomePage].
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
            final l10n = AppLocalizations.of(context)!;
            return SwitchListTile(
              secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode, color: cs.primary),
              title: Text(isDark ? l10n.darkModeLabel : l10n.lightModeLabel),
              subtitle: Text(isDark ? l10n.switchToLightThemeSubtitle : l10n.switchToDarkThemeSubtitle),
              value: isDark,
              onChanged: (val) {
                ref.read(themeModeProvider.notifier).setMode(val ? ThemeMode.dark : ThemeMode.light);
              },
            );
          }),

          // App icon toggle
          Consumer(builder: (context, ref, child) {
            final useDarkIcon = ref.watch(appIconProvider);
            final l10n = AppLocalizations.of(context)!;
            return SwitchListTile(
              secondary: Icon(Icons.grid_view, color: cs.primary),
              title: Text(useDarkIcon ? l10n.appIconLabel : l10n.appIconLightLabel),
              subtitle: Text(useDarkIcon ? l10n.appIconDarkSubtitle : l10n.appIconLightSubtitle),
              value: useDarkIcon,
              onChanged: (val) {
                ref.read(appIconProvider.notifier).setDarkIcon(val);
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

          // Language
          Consumer(builder: (context, ref, child) {
            final locale = ref.watch(localeProvider);
            final currentLabel = appLanguageOptions
                .firstWhere((o) => o['code'] == locale.languageCode,
                    orElse: () => {'label': 'English'})
                ['label'] as String;
            return ListTile(
              leading: Icon(Icons.language, color: cs.primary),
              title: const Text('Language'),
              subtitle: Text(currentLabel),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (ctx) => SimpleDialog(
                    title: const Text('Select Language'),
                    children: appLanguageOptions
                        .where((o) => o['code'] != null)
                        .map((o) => ListTile(
                              leading: o['code'] == locale.languageCode
                                  ? Icon(Icons.check, color: cs.primary)
                                  : const SizedBox(width: 24),
                              title: Text(o['label'] as String),
                              onTap: () {
                                ref.read(localeProvider.notifier).setLocale(o['code']!);
                                Navigator.pop(ctx);
                              },
                            ))
                        .toList(),
                  ),
                );
              },
            );
          }),

          // Account Settings
          ListenableBuilder(
            listenable: ConnectivityService(),
            builder: (context, _) {
              final connected = ConnectivityService().isOnline;
              final l10n = AppLocalizations.of(context)!;
              return ListTile(
                leading: connected
                    ? Icon(Icons.person, color: cs.primary)
                    : Icon(Icons.person_outline, color: cs.outline),
                title: Text(l10n.settingsAccountTitle,
                    style: TextStyle(color: connected ? cs.onSurface : cs.outline)),
                subtitle: Text(
                    connected ? l10n.settingsAccountSubtitleOnline : l10n.settingsAccountSubtitleOffline,
                    style: TextStyle(color: connected ? cs.onSurfaceVariant : cs.outline)),
                onTap: connected
                    ? () => _showChangePasswordDialog(context)
                    : null,
              );
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

final _upperRE = RegExp(r'[A-Z]');
final _lowerRE = RegExp(r'[a-z]');
final _digitRE = RegExp(r'[0-9]');

/// Displays a dialog for changing the student's password.
///
/// Requires the user to enter their current password and a new one
/// (min 8 chars, uppercase, lowercase, digit). On success, sends a
/// `POST /student/change-password` request and shows a snackbar.
/// The [context] must be within a widget tree that has [ApiClient] available.
void _showChangePasswordDialog(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context)!;
  final oldPwdCtrl = TextEditingController();
  final newPwdCtrl = TextEditingController();
  final confirmPwdCtrl = TextEditingController();

  showDialog(
    context: context,
    builder: (ctx) {
      bool obscureOld = true;
      bool obscureNew = true;
      bool obscureConfirm = true;
      String? error;
      bool loading = false;
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(l10n.dialogChangePasswordTitle, style: TextStyle(fontWeight: AppSpacing.weightDisplay, fontSize: 18.sp)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.dialogChangePasswordBody, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13.sp)),
                SizedBox(height: 16.h),
                TextField(
                  controller: oldPwdCtrl,
                  obscureText: obscureOld,
                  decoration: InputDecoration(
                    labelText: l10n.labelCurrentPassword,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(obscureOld ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => obscureOld = !obscureOld),
                    ),
                  ),
                ),
                SizedBox(height: 12.h),
                TextField(
                  controller: newPwdCtrl,
                  obscureText: obscureNew,
                  decoration: InputDecoration(
                    labelText: l10n.labelNewPassword,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => obscureNew = !obscureNew),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(top: 4.h),
                  child: Text(l10n.hintPasswordRequirements,
                      style: TextStyle(color: cs.outline, fontSize: 11.sp)),
                ),
                SizedBox(height: 12.h),
                TextField(
                  controller: confirmPwdCtrl,
                  obscureText: obscureConfirm,
                  decoration: InputDecoration(
                    labelText: l10n.labelConfirmPassword,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => obscureConfirm = !obscureConfirm),
                    ),
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: EdgeInsets.only(top: 8.h),
                    child: Text(error!, style: TextStyle(color: cs.error, fontSize: 13.sp)),
                  ),
                if (loading)
                  Padding(
                    padding: EdgeInsets.only(top: 12.h),
                    child: CircularProgressIndicator(color: cs.tertiary),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: loading ? null : () => Navigator.of(ctx).pop(),
                child: Text(l10n.buttonCancel),
              ),
              ElevatedButton(
                onPressed: loading ? null : () async {
                  final old = oldPwdCtrl.text;
                  final pwd = newPwdCtrl.text;
                  if (old.isEmpty) { setState(() => error = l10n.errorCurrentPasswordRequired); return; }
                  if (pwd.length < 8) { setState(() => error = l10n.errorPasswordMinLength); return; }
                  if (pwd != confirmPwdCtrl.text) { setState(() => error = l10n.errorPasswordsDoNotMatch); return; }
                  if (!pwd.contains(_upperRE) || !pwd.contains(_lowerRE) || !pwd.contains(_digitRE)) {
                    setState(() => error = l10n.errorPasswordComplexity);
                    return;
                  }
                  setState(() { error = null; loading = true; });
                  try {
                    await ApiClient.post('/student/change-password', data: {
                      'old_password': old,
                      'new_password': pwd,
                    });
                    if (context.mounted) {
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.snackbarPasswordChanged),
                            backgroundColor: cs.tertiary, behavior: SnackBarBehavior.floating),
                      );
                    }
                  } catch (_) {
                    setState(() { loading = false; error = l10n.errorPasswordChangeFailed; });
                  }
                },
                child: Text(l10n.buttonUpdatePassword),
              ),
            ],
          );
        },
      );
    },
  ).then((_) {
    oldPwdCtrl.dispose();
    newPwdCtrl.dispose();
    confirmPwdCtrl.dispose();
  });
}
