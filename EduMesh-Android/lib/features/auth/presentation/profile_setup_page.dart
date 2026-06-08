import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:edumesh_android/core/network/api_client.dart';
import 'package:edumesh_android/widgets/connection_gate.dart';
import 'package:edumesh_android/pages/app_shell.dart';
import 'package:edumesh_android/core/constants/app_spacing.dart';

/// A post-registration page prompting the student to set a display name and
/// select their grade before entering the main app.
///
/// Loads available grades from the hub via `/grades` and submits the chosen
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
  String _selectedGrade = '';
  List<String> _grades = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.username);
    _loadGrades();
  }

  Future<void> _loadGrades() async {
    try {
      final res = await ApiClient.get('/grades');
      if (res.data is List) {
        final grades = (res.data as List).map((g) => (g is Map ? g['name']?.toString() ?? '' : g.toString())).where((n) => n.isNotEmpty).toList();
        if (mounted) setState(() { _grades = grades; if (grades.isNotEmpty) _selectedGrade = grades[0]; _loading = false; });
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveAndContinue() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ApiClient.post('/student/profile/update', data: {'name': name, 'grade': _selectedGrade});
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ConnectionGate(child: AppShell())),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 48.h),
              Icon(Icons.school_rounded, size: 48.sp, color: cs.primary),
              SizedBox(height: 16.h),
              Text('Welcome!',
                  style: GoogleFonts.atkinsonHyperlegible(fontSize: 32.sp, fontWeight: AppSpacing.weightDisplay, color: cs.primary)),
              SizedBox(height: 4.h),
              Text("Let's set up your profile",
                  style: GoogleFonts.atkinsonHyperlegible(fontSize: 16.sp, color: cs.onSurfaceVariant)),
              SizedBox(height: 40.h),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else ...[
                Text('Display Name',
                    style: GoogleFonts.atkinsonHyperlegible(fontSize: 13.sp, fontWeight: AppSpacing.weightStrong, color: cs.onSurfaceVariant)),
                SizedBox(height: 6.h),
                TextField(
                  controller: _nameController,
                  style: GoogleFonts.atkinsonHyperlegible(fontSize: 15.sp, color: cs.onSurface),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: cs.surfaceContainerHighest,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
                    contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                  ),
                ),
                SizedBox(height: 20.h),
                Text('Grade',
                    style: GoogleFonts.atkinsonHyperlegible(fontSize: 13.sp, fontWeight: AppSpacing.weightStrong, color: cs.onSurfaceVariant)),
                SizedBox(height: 6.h),
                DropdownButtonFormField<String>(
                  initialValue: _selectedGrade.isNotEmpty && _grades.contains(_selectedGrade) ? _selectedGrade : null,
                  items: _grades.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                  onChanged: (v) => setState(() => _selectedGrade = v ?? ''),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: cs.surfaceContainerHighest,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
                    contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                  ),
                ),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _saveAndContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                  ),
                  child: _saving
                      ? SizedBox(width: 20.sp, height: 20.sp, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                      : Text('Continue',
                          style: GoogleFonts.atkinsonHyperlegible(fontSize: 16.sp, fontWeight: AppSpacing.weightStrong)),
                ),
              ),
              SizedBox(height: 32.h),
            ],
          ),
        ),
      ),
    );
  }
}
