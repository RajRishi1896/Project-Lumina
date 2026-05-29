import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../auth/data/auth_service.dart';
import '../../../../shared/services/mock_data_service.dart';
import '../../data/teacher_repository.dart';

class DangerZoneTab extends StatefulWidget {
  const DangerZoneTab({super.key});

  @override
  State<DangerZoneTab> createState() => _DangerZoneTabState();
}

class _DangerZoneTabState extends State<DangerZoneTab> {
  List<Map<String, dynamic>> _scholars = [];
  List<Map<String, dynamic>> _teachers = [];
  bool _loadingScholars = true;
  bool _loadingTeachers = true;
  String _studentSearch = '';
  String _teacherSearch = '';
  final _studentSearchCtrl = TextEditingController();
  final _teacherSearchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _studentSearchCtrl.dispose();
    _teacherSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await Future.wait([_loadScholars(), _loadTeachers()]);
  }

  Future<void> _loadScholars() async {
    setState(() => _loadingScholars = true);
    try {
      final data = await TeacherRepository.getScholars();
      if (mounted) setState(() { _scholars = data; _loadingScholars = false; });
    } catch (e) {
      if (mounted) setState(() => _loadingScholars = false);
    }
  }

  Future<void> _loadTeachers() async {
    setState(() => _loadingTeachers = true);
    try {
      final data = await TeacherRepository.getTeachers();
      if (mounted) setState(() { _teachers = data; _loadingTeachers = false; });
    } catch (e) {
      if (mounted) setState(() => _loadingTeachers = false);
    }
  }

  Future<void> _resetStudentPwd(String scholarId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Student Password?'),
        content: const Text('Password will be reset to "lumina2026". Student will be prompted to change on next login.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await TeacherRepository.resetStudentPassword(scholarId);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Student password reset')));
        _loadScholars();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _deleteStudent(String scholarId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "$name"?'),
        content: const Text('This will permanently remove the student account and all activity logs.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await TeacherRepository.deleteStudent(scholarId);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Student deleted')));
        _loadScholars();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _forceResetTeacherPwd(String username) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reset "${username}" password?'),
        content: const Text('Password will be reset to "lumina2026".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await TeacherRepository.forceResetTeacherPassword(username);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Teacher password reset')));
        _loadTeachers();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _deleteTeacher(String username) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete teacher "$username"?'),
        content: const Text('This will permanently remove the teacher profile.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await TeacherRepository.deleteTeacher(username);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Teacher deleted')));
        _loadTeachers();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _disableDefaultAdmin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disable Default Admin?'),
        content: const Text('This will lock the default "admin" account. Ensure at least one teacher profile exists. This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Disable', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await TeacherRepository.disableDefaultAdmin();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Default admin disabled')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (AuthService.isDemoMode) _buildDemoActions(cs),
          SizedBox(height: 16.h),
          _buildStudentSection(cs),
          SizedBox(height: 24.h),
          _buildTeacherSection(cs),
          SizedBox(height: 24.h),
          _buildDisableAdminSection(cs),
        ],
      ),
    );
  }

  Widget _buildStudentSection(ColorScheme cs) {
    final filtered = _scholars.where((s) =>
        _studentSearch.isEmpty ||
        (s['name']?.toString().toLowerCase() ?? '').contains(_studentSearch.toLowerCase()) ||
        (s['id']?.toString().toLowerCase() ?? '').contains(_studentSearch.toLowerCase())).toList();

    return Card(
      color: cs.surfaceContainer,
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Manage Students',
                style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700, color: cs.onSurface)),
            SizedBox(height: 12.h),
            TextFormField(
              controller: _studentSearchCtrl,
              decoration: const InputDecoration(
                labelText: 'Search students...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _studentSearch = v),
            ),
            SizedBox(height: 12.h),
            if (_loadingScholars)
              const Center(child: CircularProgressIndicator())
            else if (filtered.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 24.h),
                child: Center(child: Text('No students found', style: TextStyle(color: cs.onSurfaceVariant))),
              )
            else
              ...List.generate(filtered.length, (i) {
                final s = filtered[i];
                final needsReset = (s['reset_required'] ?? 0) == 1;
                return ListTile(
                  dense: true,
                  title: Text(s['name'] ?? 'Unknown'),
                  subtitle: Text(s['id'] ?? ''),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (needsReset)
                        Container(
                          margin: EdgeInsets.only(right: 8.w),
                          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('Reset Pending', style: TextStyle(fontSize: 10.sp, color: Colors.orange.shade900)),
                        ),
                      IconButton(
                        icon: Icon(Icons.lock_reset, color: cs.primary, size: 20.sp),
                        tooltip: 'Reset password',
                        onPressed: () => _resetStudentPwd(s['id'] ?? ''),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline, color: cs.error, size: 20.sp),
                        tooltip: 'Delete student',
                        onPressed: () => _deleteStudent(s['id'] ?? '', s['name'] ?? ''),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildTeacherSection(ColorScheme cs) {
    final filtered = _teachers.where((t) =>
        _teacherSearch.isEmpty ||
        (t['name']?.toString().toLowerCase() ?? '').contains(_teacherSearch.toLowerCase()) ||
        (t['username']?.toString().toLowerCase() ?? '').contains(_teacherSearch.toLowerCase())).toList();

    return Card(
      color: cs.surfaceContainer,
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Manage Teachers',
                style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700, color: cs.onSurface)),
            SizedBox(height: 12.h),
            TextFormField(
              controller: _teacherSearchCtrl,
              decoration: const InputDecoration(
                labelText: 'Search teachers...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _teacherSearch = v),
            ),
            SizedBox(height: 12.h),
            if (_loadingTeachers)
              const Center(child: CircularProgressIndicator())
            else if (filtered.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 24.h),
                child: Center(child: Text('No teachers found', style: TextStyle(color: cs.onSurfaceVariant))),
              )
            else
              ...List.generate(filtered.length, (i) {
                final t = filtered[i];
                final needsReset = (t['reset_required'] ?? 0) == 1;
                return ListTile(
                  dense: true,
                  title: Text(t['name'] ?? t['username'] ?? 'Unknown'),
                  subtitle: Text('${t['department'] ?? 'General'}  •  ${t['username'] ?? ''}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (needsReset)
                        Container(
                          margin: EdgeInsets.only(right: 8.w),
                          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('Reset Pending', style: TextStyle(fontSize: 10.sp, color: Colors.orange.shade900)),
                        ),
                      IconButton(
                        icon: Icon(Icons.lock_reset, color: cs.primary, size: 20.sp),
                        tooltip: 'Force reset password',
                        onPressed: () => _forceResetTeacherPwd(t['username'] ?? ''),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline, color: cs.error, size: 20.sp),
                        tooltip: 'Delete teacher',
                        onPressed: () => _deleteTeacher(t['username'] ?? ''),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildDemoActions(ColorScheme cs) {
    return Card(
      color: cs.primary.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: cs.primary.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.science_rounded, size: 18.sp, color: cs.primary),
                SizedBox(width: 8.w),
                Text('Demo Actions',
                    style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w700,
                        color: cs.primary)),
              ],
            ),
            SizedBox(height: 12.h),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _scholars = MockDataService.getSampleScholars();
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Sample students loaded')),
                      );
                    },
                    icon: const Icon(Icons.people, size: 18),
                    label: const Text('Load Students'),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _teachers = MockDataService.getSampleTeachers();
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Sample teachers loaded')),
                      );
                    },
                    icon: const Icon(Icons.school, size: 18),
                    label: const Text('Load Teachers'),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8.h),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _scholars = [];
                        _teachers = [];
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Demo data cleared')),
                      );
                    },
                    icon: const Icon(Icons.clear_all, size: 18),
                    label: const Text('Clear All'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDisableAdminSection(ColorScheme cs) {
    return Card(
      color: cs.surfaceContainer,
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Disable Default Admin',
                style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700, color: cs.error)),
            SizedBox(height: 8.h),
            Text('Lock the default "admin" account after creating teacher profiles. This cannot be undone.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.sp)),
            SizedBox(height: 12.h),
            ElevatedButton.icon(
              onPressed: _disableDefaultAdmin,
              icon: const Icon(Icons.lock),
              style: ElevatedButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError),
              label: const Text('Disable Default Admin'),
            ),
          ],
        ),
      ),
    );
  }
}
