import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../auth/data/auth_service.dart';
import '../../data/teacher_repository.dart';

class SecurityTab extends StatefulWidget {
  const SecurityTab({super.key});

  @override
  State<SecurityTab> createState() => _SecurityTabState();
}

class _SecurityTabState extends State<SecurityTab> {
  // Change Password
  final _oldPwdCtrl = TextEditingController();
  final _newPwdCtrl = TextEditingController();
  final _confirmPwdCtrl = TextEditingController();
  final _changePwdFormKey = GlobalKey<FormState>();

  // Create Teacher Profile
  final _teacherUserCtrl = TextEditingController();
  final _teacherPwdCtrl = TextEditingController();
  final _teacherNameCtrl = TextEditingController();
  final _teacherDeptCtrl = TextEditingController(text: 'General');
  final _createTeacherFormKey = GlobalKey<FormState>();

  bool _changePwdLoading = false;
  bool _createTeacherLoading = false;

  @override
  void dispose() {
    _oldPwdCtrl.dispose();
    _newPwdCtrl.dispose();
    _confirmPwdCtrl.dispose();
    _teacherUserCtrl.dispose();
    _teacherPwdCtrl.dispose();
    _teacherNameCtrl.dispose();
    _teacherDeptCtrl.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_changePwdFormKey.currentState!.validate()) return;
    setState(() => _changePwdLoading = true);
    try {
      final username = await AuthService().getLoggedUsername() ?? 'admin';
      await TeacherRepository.changePassword(
        username: username,
        oldPassword: _oldPwdCtrl.text,
        newPassword: _newPwdCtrl.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Password changed successfully')));
        _oldPwdCtrl.clear();
        _newPwdCtrl.clear();
        _confirmPwdCtrl.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Password change failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _changePwdLoading = false);
    }
  }

  Future<void> _createTeacher() async {
    if (!_createTeacherFormKey.currentState!.validate()) return;
    setState(() => _createTeacherLoading = true);
    try {
      await TeacherRepository.createTeacherProfile(
        username: _teacherUserCtrl.text.trim(),
        password: _teacherPwdCtrl.text,
        name: _teacherNameCtrl.text.trim(),
        department: _teacherDeptCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Teacher profile created')));
        _teacherUserCtrl.clear();
        _teacherPwdCtrl.clear();
        _teacherNameCtrl.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Creation failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _createTeacherLoading = false);
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
          _buildChangePasswordCard(cs),
          SizedBox(height: 24.h),
          _buildCreateTeacherCard(cs),
        ],
      ),
    );
  }

  Widget _buildChangePasswordCard(ColorScheme cs) {
    return Card(
      color: cs.surfaceContainer,
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Form(
          key: _changePwdFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Change Password',
                  style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700, color: cs.onSurface)),
              SizedBox(height: 16.h),
              TextFormField(
                controller: _oldPwdCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Current Password', border: OutlineInputBorder()),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              SizedBox(height: 12.h),
              TextFormField(
                controller: _newPwdCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New Password', border: OutlineInputBorder()),
                validator: (v) => v == null || v.length < 4 ? 'At least 4 characters' : null,
              ),
              SizedBox(height: 12.h),
              TextFormField(
                controller: _confirmPwdCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirm New Password', border: OutlineInputBorder()),
                validator: (v) => v != _newPwdCtrl.text ? 'Passwords do not match' : null,
              ),
              SizedBox(height: 16.h),
              ElevatedButton(
                onPressed: _changePwdLoading ? null : _changePassword,
                child: _changePwdLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Update Password'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreateTeacherCard(ColorScheme cs) {
    return Card(
      color: cs.surfaceContainer,
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Form(
          key: _createTeacherFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Create Teacher Profile',
                  style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700, color: cs.onSurface)),
              SizedBox(height: 16.h),
              TextFormField(
                controller: _teacherUserCtrl,
                decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder()),
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              SizedBox(height: 12.h),
              TextFormField(
                controller: _teacherPwdCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                validator: (v) => v == null || v.length < 4 ? 'At least 4 characters' : null,
              ),
              SizedBox(height: 12.h),
              TextFormField(
                controller: _teacherNameCtrl,
                decoration: const InputDecoration(labelText: 'Display Name (optional)', border: OutlineInputBorder()),
              ),
              SizedBox(height: 12.h),
              TextFormField(
                controller: _teacherDeptCtrl,
                decoration: const InputDecoration(labelText: 'Department', border: OutlineInputBorder()),
              ),
              SizedBox(height: 16.h),
              ElevatedButton(
                onPressed: _createTeacherLoading ? null : _createTeacher,
                child: _createTeacherLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Create Profile'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
