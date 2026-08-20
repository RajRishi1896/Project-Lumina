import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../widgets/connection_gate.dart';
import '../../../pages/app_shell.dart';
import '../../../l10n/app_localizations.dart';
import '../data/auth_service.dart';
import 'login_page.dart';
import 'welcome_page.dart';

/// Routes to the [ProfilePickerPage] when other profiles remain on the
/// device after logout, otherwise to the [WelcomePage]. Used by the settings
/// sheet, the password-change flow, and [ApiClient.onForceLogout].
Future<void> routeAfterLogout(NavigatorState navigator) async {
  final profiles = await AuthService().getKnownProfiles();
  final target = profiles.isNotEmpty ? const ProfilePickerPage() : const WelcomePage();
  unawaited(navigator.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => target),
    (route) => false,
  ));
}

/// Lets the user choose which student profile is active on this device.
///
/// Lists every profile known to [AuthService]. Tapping a profile switches to
/// it without a password (fully offline) and rebuilds the [AppShell] so the
/// new student's dashboard, progress, and quiz data load fresh. An "Add
/// profile" action hands off to the normal [LoginPage] register flow.
class ProfilePickerPage extends StatefulWidget {
  const ProfilePickerPage({super.key});

  @override
  State<ProfilePickerPage> createState() => _ProfilePickerPageState();
}

class _ProfilePickerPageState extends State<ProfilePickerPage> {
  static final RegExp _whitespaceRE = RegExp(r'\s+');

  List<Map<String, dynamic>> _profiles = [];
  String? _activeUserId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final auth = AuthService();
    final profiles = await auth.getKnownProfiles();
    final activeId = await auth.getUniqueUserId();
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      _activeUserId = activeId;
      _loading = false;
    });
  }

  String _initials(String name, AppLocalizations l10n) {
    if (name.trim().isEmpty) return l10n.initialsFallback;
    final parts = name.trim().split(_whitespaceRE);
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return parts[0][0].toUpperCase();
  }

  Future<void> _switchTo(Map<String, dynamic> profile) async {
    final ok = await AuthService().switchToProfile(profile['userId']?.toString() ?? '');
    if (!mounted) return;
    if (!ok) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l10n.profileSwitchFailed)));
      return;
    }
    unawaited(Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ConnectionGate(child: AppShell())),
      (route) => false,
    ));
  }

  void _addProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.profilePickerTitle),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w, vertical: AppSpacing.md.h),
              children: [
                if (_profiles.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl.h),
                    child: Text(
                      l10n.profilePickerEmpty,
                      textAlign: TextAlign.center,
                      style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  )
                else
                  ..._profiles.map((profile) {
                    final userId = profile['userId']?.toString() ?? '';
                    final displayName = profile['displayName']?.toString() ?? '';
                    final username = profile['username']?.toString() ?? '';
                    final name = displayName.isNotEmpty ? displayName : username;
                    final isActive = userId.isNotEmpty && userId == _activeUserId;
                    return Card(
                      margin: EdgeInsets.only(bottom: AppSpacing.md.h),
                      child: ListTile(
                        onTap: isActive ? null : () => _switchTo(profile),
                        leading: CircleAvatar(
                          radius: 20.r,
                          backgroundColor: cs.primaryContainer,
                          child: Text(
                            _initials(name, l10n),
                            style: tt.titleMedium?.copyWith(
                              color: cs.onPrimaryContainer,
                              fontWeight: AppSpacing.weightStrong,
                            ),
                          ),
                        ),
                        title: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodyMedium?.copyWith(
                            color: isActive ? cs.onSurface : cs.onSurface,
                            fontWeight: isActive ? AppSpacing.weightStrong : AppSpacing.weightBody,
                          ),
                        ),
                        subtitle: username.isNotEmpty
                            ? Text('@$username',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant))
                            : null,
                        trailing: isActive
                            ? Container(
                                padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm.w, vertical: AppSpacing.xs.h),
                                decoration: BoxDecoration(
                                  color: cs.primaryContainer,
                                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                                ),
                                child: Text(
                                  l10n.profilePickerCurrent,
                                  style: tt.labelSmall?.copyWith(
                                    color: cs.onPrimaryContainer,
                                    fontWeight: AppSpacing.weightStrong,
                                  ),
                                ),
                              )
                            : Icon(Icons.chevron_right_rounded, color: cs.outline),
                      ),
                    );
                  }),
                SizedBox(height: AppSpacing.xl.h),
                Card(
                  margin: EdgeInsets.only(bottom: AppSpacing.md.h),
                  child: ListTile(
                    onTap: _addProfile,
                    leading: CircleAvatar(
                      radius: 20.r,
                      backgroundColor: cs.surfaceContainerHighest,
                      child: Icon(Icons.person_add_rounded, color: cs.primary, size: 20.sp),
                    ),
                    title: Text(
                      l10n.profilePickerAddProfile,
                      style: tt.bodyMedium?.copyWith(color: cs.primary, fontWeight: AppSpacing.weightStrong),
                    ),
                    subtitle: Text(
                      l10n.profilePickerAddProfileSubtitle,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}