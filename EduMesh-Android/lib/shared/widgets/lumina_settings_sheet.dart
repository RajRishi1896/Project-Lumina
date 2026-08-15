import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:app_settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/password_strength.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/services/connectivity_service.dart';
import '../../../shared/services/share_server.dart';
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

    final items = _settingsItems(context, ref);
    return Container(
      padding: EdgeInsets.only(top: AppSpacing.sm.h),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusXl.r)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
          child: ListView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.only(bottom: AppSpacing.section.h),
            itemCount: items.length,
            itemBuilder: (_, i) => items[i],
          ),
        ),
      ),
    );
  }

  /// The ordered list of tiles shown in this sheet.
  List<Widget> _settingsItems(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return [
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
            child: Text(AppLocalizations.of(context)!.settingsSheetTitle,
                style: tt.titleLarge?.copyWith(
                    color: cs.onSurface)),
          ),

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

          // Share files toggle
          const _ShareToggleTile(),

          // Storage
          ListTile(
            leading: Icon(Icons.storage, color: cs.primary),
            title: Text(AppLocalizations.of(context)!.storageOfflineLibraryTitle),
            subtitle: Text(AppLocalizations.of(context)!.storageOfflineLibrarySubtitle),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const OfflineLibraryPage()));
            },
          ),

          // Network
          ListTile(
            leading: Icon(Icons.wifi, color: cs.primary),
            title: Text(AppLocalizations.of(context)!.networkSettingsTitle),
            subtitle: Text(AppLocalizations.of(context)!.networkSettingsSubtitle),
            onTap: () {
              Navigator.pop(context);
              AppSettings.openAppSettings(type: AppSettingsType.wifi);
            },
          ),

          // Language
          Consumer(builder: (context, ref, child) {
            final locale = ref.watch(localeProvider);
            final l10n = AppLocalizations.of(context)!;
            final currentLabel = _languageLabel(locale.languageCode);
            return ListTile(
              leading: Icon(Icons.language, color: cs.primary),
              title: Text(l10n.settingsLanguageTitle),
              subtitle: Text(currentLabel),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (ctx) => SimpleDialog(
                    title: Text(l10n.settingsLanguagePickerTitle),
                    children: appLanguageOptions
                        .map((o) => ListTile(
                              leading: o['code'] == locale.languageCode
                                  ? Icon(Icons.check, color: cs.primary)
                                  : const SizedBox(width: AppSpacing.xxl),
                              title: Text(_languageLabel(o['code']!)),
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
                    style: tt.bodyMedium?.copyWith(color: connected ? cs.onSurface : cs.outline)),
                subtitle: Text(
                    connected ? l10n.settingsAccountSubtitleOnline : l10n.settingsAccountSubtitleOffline,
                    style: tt.bodySmall?.copyWith(color: connected ? cs.onSurfaceVariant : cs.outline)),
                onTap: connected
                    ? () => _showChangePasswordDialog(context)
                    : null,
              );
            },
          ),

          const Divider(),

          ListTile(
            leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
            title: Text(AppLocalizations.of(context)!.logOutButtonLabel, style: tt.titleSmall?.copyWith(color: Theme.of(context).colorScheme.error)),
            onTap: () async {
              await AuthService().logout();
              if (context.mounted) {
                unawaited(Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const WelcomePage()),
                  (route) => false,
                ));
              }
            },
          ),
SizedBox(height: AppSpacing.sm.h),
    ];
  }
}

/// A settings toggle that controls whether nearby students may download
/// files saved on this phone. When switched ON the [ShareServer] starts
/// serving; when OFF it stops.
class _ShareToggleTile extends StatefulWidget {
  const _ShareToggleTile();

  @override
  State<_ShareToggleTile> createState() => _ShareToggleTileState();
}

class _ShareToggleTileState extends State<_ShareToggleTile> {
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() => _enabled = prefs.getBool(ShareServer.enabledPrefKey) ?? false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return SwitchListTile(
      secondary: Icon(Icons.share, color: cs.primary),
      title: Text(l10n.shareSettingsTitle),
      subtitle: Text(l10n.shareSettingsDescription),
      value: _enabled,
      onChanged: (val) async {
        setState(() => _enabled = val);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(ShareServer.enabledPrefKey, val);
        if (val) {
          unawaited(ShareServer().start().catchError((_) {}));
        } else {
          unawaited(ShareServer().stop());
        }
      },
    );
  }
}

/// Displays a dialog for changing the student's password.
///
/// Requires the user to enter their current password and a new one
/// (min 8 chars, uppercase, lowercase, digit). On success, sends a
/// `POST /student/change-password` request and shows a snackbar.
/// The [context] must be within a widget tree that has [ApiClient] available.
void _showChangePasswordDialog(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  final tt = Theme.of(context).textTheme;
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
            title: Text(l10n.dialogChangePasswordTitle, style: tt.titleLarge?.copyWith(fontWeight: AppSpacing.weightDisplay)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.dialogChangePasswordBody, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                SizedBox(height: AppSpacing.lg.h),
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
                SizedBox(height: AppSpacing.md.h),
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
                  padding: EdgeInsets.only(top: AppSpacing.xs.h),
                  child: Text(l10n.hintPasswordRequirements,
                      style: tt.labelSmall?.copyWith(color: cs.outline)),
                ),
                SizedBox(height: AppSpacing.md.h),
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
                    padding: EdgeInsets.only(top: AppSpacing.sm.h),
                    child: Text(error!, style: tt.bodySmall?.copyWith(color: cs.error)),
                  ),
                if (loading)
                  Padding(
                    padding: EdgeInsets.only(top: AppSpacing.md.h),
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
                  if (!pwd.contains(upperCaseRegExp) || !pwd.contains(lowerCaseRegExp) || !pwd.contains(digitRegExp)) {
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

String _languageLabel(String code) {
  switch (code) {
    case 'en': return 'English';
    case 'hi': return 'हिन्दी';
    case 'kn': return 'ಕನ್ನಡ';
    case 'fr': return 'Français';
    case 'ta': return 'தமிழ்';
    case 'te': return 'తెలుగు';
    default: return code;
  }
}
