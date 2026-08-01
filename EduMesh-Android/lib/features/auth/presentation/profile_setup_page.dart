import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:edumesh_android/core/network/api_client.dart';
import 'package:edumesh_android/features/auth/data/auth_service.dart';
import 'package:edumesh_android/core/services/mutation_queue.dart';
import 'package:edumesh_android/widgets/connection_gate.dart';
import 'package:edumesh_android/pages/app_shell.dart';
import 'package:edumesh_android/core/constants/app_spacing.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A post-registration page prompting the student to set a display name and
/// select their grade before entering the main app.
///
/// Loads available grades from the hub via `/student/grades` and submits the chosen
/// profile to `/student/profile/update` before navigating to [AppShell].
class ProfileSetupPage extends StatefulWidget {
  /// The username from the registration step, used as the initial display name.
  final String username;
  const ProfileSetupPage({super.key, required this.username});

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage> {
  late TextEditingController _nameController;
  String _selectedGrade = 'General';
  List<String> _grades = [];
  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.username);
    _loadGrades();
  }

  static const String _fallbackGrade = 'General';

  Future<void> _loadGrades() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getStringList('cached_grades');
      if (cached != null && cached.isNotEmpty) {
        if (mounted) setState(() { _grades = cached; _selectedGrade = cached.first; _loading = false; });
      }

      final res = await ApiClient.get('/student/grades');
      if (res.data is List) {
        final grades = (res.data as List).map((g) => (g is Map ? g['name']?.toString() ?? '' : g.toString())).where((n) => n.isNotEmpty).toList();
        if (grades.isNotEmpty) {
          await prefs.setStringList('cached_grades', grades);
          if (mounted) setState(() { _grades = grades; _selectedGrade = grades.first; _loadError = null; _loading = false; });
        } else {
          if (mounted) setState(() { _grades = [_fallbackGrade]; _selectedGrade = _fallbackGrade; _loadError = null; _loading = false; });
        }
        return;
      }
    } catch (_) {}
    if (_grades.isEmpty) {
      if (mounted) setState(() { _grades = [_fallbackGrade]; _selectedGrade = _fallbackGrade; _loadError = null; _loading = false; });
    } else {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _retryLoadGrades() async {
    setState(() { _loading = true; _loadError = null; });
    await _loadGrades();
  }

  Future<void> _saveAndContinue() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _saving || _loadError != null) return;
    setState(() => _saving = true);
    try {
      await MutationQueue().enqueue('/student/profile/update', method: 'POST', body: {'name': name, 'grade': _selectedGrade});
      await AuthService().saveGrade(_selectedGrade);
      await AuthService().setDisplayName(name);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    if (!mounted) return;
    unawaited(Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ConnectionGate(child: AppShell())),
    ));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.xxl.w, vertical: AppSpacing.lg.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: AppSpacing.touchTarget.h),
              SvgPicture.asset(
                Theme.of(context).brightness == Brightness.dark ? 'assets/images/logo-dark.svg' : 'assets/images/logo-light.svg',
                width: 48.sp,
                height: 48.sp,
              ),
              SizedBox(height: AppSpacing.lg.h),
              Text(l10n.profileSetupTitle,
                  style: tt.displaySmall?.copyWith(color: cs.primary)),
              SizedBox(height: AppSpacing.xs.h),
              Text(l10n.profileSetupSubtitle,
                  style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
              SizedBox(height: AppSpacing.sectionLg.h),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else ...[
                if (_loadError != null) ...[
                  Text(_loadError!, style: tt.bodyMedium?.copyWith(color: cs.error)),
                  SizedBox(height: AppSpacing.md.h),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _retryLoadGrades,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(l10n.errorRetryButton),
                  ),
                  SizedBox(height: AppSpacing.sm.h),
                ],
                Text(l10n.labelDisplayName,
                    style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
                SizedBox(height: AppSpacing.sm.h),
                TextField(
                  controller: _nameController,
                  style: tt.bodyLarge?.copyWith(color: cs.onSurface),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: cs.surfaceContainerHighest,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
                    contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.md.w, vertical: AppSpacing.md.h),
                  ),
                ),
                SizedBox(height: AppSpacing.xl.h),
                Text(l10n.editProfileLabelGrade,
                    style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
                SizedBox(height: AppSpacing.sm.h),
                DropdownButtonFormField<String>(
                  initialValue: _selectedGrade.isNotEmpty && _grades.contains(_selectedGrade) ? _selectedGrade : null,
                  items: _grades.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                  onChanged: _grades.isEmpty ? null : (v) => setState(() => _selectedGrade = v ?? ''),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: cs.surfaceContainerHighest,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
                    contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.md.w, vertical: AppSpacing.md.h),
                  ),
                ),
              ],
              SizedBox(height: AppSpacing.xl.h),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving || _loadError != null ? null : _saveAndContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.md.h),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                  ),
                  child: _saving
                      ? SizedBox(width: 20.sp, height: 20.sp, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                      : Text(l10n.buttonContinue),
                ),
              ),
              SizedBox(height: AppSpacing.section.h),
            ],
          ),
        ),
      ),
    );
  }
}
