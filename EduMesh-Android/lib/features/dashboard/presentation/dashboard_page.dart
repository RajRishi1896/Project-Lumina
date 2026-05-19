import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/lumina_colors.dart';
import '../../../core/models/resource_model.dart';
import '../../../core/services/storage_service.dart';
import '../../../shared/widgets/lumina_card.dart';
import '../../../shared/widgets/lumina_settings_sheet.dart';
import '../../../core/network/api_client.dart';
import '../../auth/data/auth_service.dart';
import 'resource_list_page.dart';
import 'video_view.dart';
import 'pdf_view.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _isConnected = false;
  bool _isChecking = true;
  String _totalStorageUsedStr = 'Calculating...';
  String _totalCapacityStr = 'Calculating...';
  double _totalStorageProgress = 0.0;
  String _appUsedStr = 'Calculating...';
  String _otherUsedStr = 'Calculating...';
  String _freeRemainingStr = 'Calculating...';
  int _appFlex = 1;
  int _otherFlex = 1;
  int _freeFlex = 1;
  
  final StorageService _storageService = StorageService();

  final List<_RecentFile> _recentFiles = []; // Empty for fresh start

  final List<(String, IconData, ResourceType)> _subjectCategories = [
    ('Math', Icons.calculate, ResourceType.textbook),
    ('Science', Icons.biotech, ResourceType.khan),
    ('English', Icons.translate, ResourceType.textbook),
    ('History', Icons.history_edu, ResourceType.textbook),
    ('Exams', Icons.quiz, ResourceType.pyq),
    ('Library', Icons.local_library, ResourceType.kiwix),
    ('Notes', Icons.description, ResourceType.notes),
  ];

  @override
  void initState() {
    super.initState();
    _checkServer();
    _calcTotalStorage();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForceResetRequired());
  }

  Future<void> _checkForceResetRequired() async {
    if (AuthService.isDemoMode) return;
    final prefs = await SharedPreferences.getInstance();
    final isStudentReset = prefs.getInt('lumina_student_reset_required') ?? 0;
    final isTeacherReset = prefs.getInt('lumina_teacher_reset_required') ?? 0;

    if ((isStudentReset == 1 || isTeacherReset == 1) && mounted) {
      _showForceResetDialog(isTeacherReset == 1);
    }
  }

  void _showForceResetDialog(bool isTeacher) {
    final TextEditingController newPasswordController = TextEditingController();
    final TextEditingController confirmPasswordController = TextEditingController();
    String? dialogError;

    showDialog(
      context: context,
      barrierDismissible: false, // Force password change
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return WillPopScope(
              onWillPop: () async => false, // Prevent back button exit
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.r),
                ),
                title: Row(
                  children: [
                    const Icon(Icons.lock_reset, color: Color(0xFFF8BC4B)),
                    SizedBox(width: 8.w),
                    Text(
                      'Password Reset Required',
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'A teacher or administrator has forced a password reset on your account. You must set a new password to continue.',
                      style: TextStyle(fontSize: 12.sp, color: Colors.grey.shade700),
                    ),
                    SizedBox(height: 16.h),
                    TextField(
                      controller: newPasswordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'New Password',
                        labelStyle: TextStyle(fontSize: 12.sp),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                      ),
                    ),
                    SizedBox(height: 12.h),
                    TextField(
                      controller: confirmPasswordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Confirm New Password',
                        labelStyle: TextStyle(fontSize: 12.sp),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                      ),
                    ),
                    if (dialogError != null) ...[
                      SizedBox(height: 8.h),
                      Text(
                        dialogError!,
                        style: TextStyle(color: Colors.red, fontSize: 11.sp),
                      ),
                    ],
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () async {
                      final newPwd = newPasswordController.text;
                      final confirmPwd = confirmPasswordController.text;
                      if (newPwd.isEmpty || confirmPwd.isEmpty) {
                        setDialogState(() => dialogError = 'Please fill all fields');
                        return;
                      }
                      if (newPwd != confirmPwd) {
                        setDialogState(() => dialogError = 'Passwords do not match');
                        return;
                      }

                      bool success = false;
                      if (isTeacher) {
                        try {
                          final prefs = await SharedPreferences.getInstance();
                          final username = prefs.getString('lumina_username') ?? '';
                          final res = await ApiClient.post('/teacher/change-password', data: {
                            'username': username,
                            'old_password': 'lumina2026',
                            'new_password': newPwd,
                          });
                          if (res.statusCode == 200) {
                            await prefs.setInt('lumina_teacher_reset_required', 0);
                            success = true;
                          }
                        } catch (e) {
                          setDialogState(() => dialogError = 'Could not update password.');
                        }
                      } else {
                        success = await AuthService().changeStudentPassword(newPwd);
                      }

                      if (success) {
                        Navigator.of(dialogContext).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Password updated successfully!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } else {
                        setDialogState(() => dialogError = 'Error updating password. Check connection.');
                      }
                    },
                    child: const Text('Update & Sync', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _checkServer() async {
    setState(() => _isChecking = true);
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      setState(() {
        _isConnected = true;
        _isChecking = false;
      });
    }
  }

  Future<void> _calcTotalStorage() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      int appDataSize = 0;
      if (await dir.exists()) {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            appDataSize += await entity.length();
          }
        }
      }
      final apkSize = await AuthService().getApkSize();
      final appUsedBytes = appDataSize + apkSize;
      
      final storageInfo = await _storageService.getStorageInfo();
      final totalBytes = storageInfo['totalBytes'] ?? (128 * 1024 * 1024 * 1024);
      final availableBytes = storageInfo['availableBytes'] ?? (64 * 1024 * 1024 * 1024);
      final otherUsedBytes = (totalBytes - availableBytes - appUsedBytes).clamp(0, totalBytes);
      
      if (mounted) {
        setState(() {
          // Format App Used
          final appMb = appUsedBytes / (1024 * 1024);
          if (appMb < 1024) {
            _appUsedStr = '${appMb.toStringAsFixed(1)} MB';
          } else {
            _appUsedStr = '${(appMb / 1024).toStringAsFixed(1)} GB';
          }

          // Format Other Used
          final otherGb = otherUsedBytes / (1024 * 1024 * 1024);
          if (otherGb < 1.0) {
            _otherUsedStr = '${(otherUsedBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
          } else {
            _otherUsedStr = '${otherGb.toStringAsFixed(1)} GB';
          }

          // Format Free Remaining
          final freeGb = availableBytes / (1024 * 1024 * 1024);
          _freeRemainingStr = '${freeGb.toStringAsFixed(1)} GB';

          // Format Total
          final totalGb = totalBytes / (1024 * 1024 * 1024);
          _totalCapacityStr = '${totalGb.toStringAsFixed(0)} GB Total';

          // Calculate Flex proportions
          _appFlex = (appUsedBytes / totalBytes * 1000).toInt().clamp(1, 1000);
          _otherFlex = (otherUsedBytes / totalBytes * 1000).toInt().clamp(1, 1000);
          _freeFlex = (availableBytes / totalBytes * 1000).toInt().clamp(1, 1000);
          
          _totalStorageProgress = ((appUsedBytes + otherUsedBytes) / totalBytes).clamp(0.0, 1.0);
          _totalStorageUsedStr = '${((appUsedBytes + otherUsedBytes) / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB used';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _appUsedStr = 'Unknown';
          _otherUsedStr = 'Unknown';
          _freeRemainingStr = 'Unknown';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                children: [
                  _buildSearchBar(context),
                  SizedBox(height: 24.h),
                  _buildStorageSection(context),
                  SizedBox(height: 24.h),
                  if (_recentFiles.isNotEmpty) _buildContinueLearning(context),
                  if (_recentFiles.isNotEmpty) SizedBox(height: 24.h),
                  _buildCategories(context),
                  SizedBox(height: 24.h),
                  if (_recentFiles.isNotEmpty) _buildRecentlyOpened(context),
                  if (_recentFiles.isNotEmpty) SizedBox(height: 24.h),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.menu, color: cs.primary, size: 24.sp),
          SizedBox(width: 12.w),
          Text(
            'Project Lumina',
            style: TextStyle(
              fontSize: 20.sp,
              fontWeight: FontWeight.w700,
              color: cs.primary,
            ),
          ),
          const Spacer(),
          _buildServerStatusBadge(),
          SizedBox(width: 8.w),
          GestureDetector(
            onTap: () => _showSettings(context),
            child: Icon(Icons.settings, color: cs.primary, size: 24.sp),
          ),
        ],
      ),
    );
  }

  Widget _buildServerStatusBadge() {
    final cs = Theme.of(context).colorScheme;

    Color bgColor;
    Color borderColor;
    Color dotColor;
    Color textColor;

    if (_isChecking) {
      bgColor = cs.surfaceContainerHighest.withAlpha(128);
      borderColor = cs.outline;
      dotColor = cs.outline;
      textColor = cs.outline;
    } else if (_isConnected) {
      bgColor = cs.secondaryContainer;
      borderColor = cs.onSecondaryContainer;
      dotColor = const Color(0xFF16A34A);
      textColor = cs.onSecondaryContainer;
    } else {
      bgColor = cs.errorContainer;
      borderColor = cs.onErrorContainer;
      dotColor = const Color(0xFFDC2626);
      textColor = cs.onErrorContainer;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8.w,
            height: 8.w,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 6.w),
          Text(
            _isChecking
                ? 'Checking...'
                : (_isConnected
                    ? 'Connected'
                    : 'Disconnected'),
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.02,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: EdgeInsets.only(top: 16.h),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant, width: 1),
      ),
      child: TextField(
        style: TextStyle(fontSize: 14.sp, color: cs.onSurface),
        decoration: InputDecoration(
          hintText: 'Search educational resources, lessons, or files...',
          hintStyle: TextStyle(fontSize: 14.sp, color: cs.onSurfaceVariant),
          prefixIcon: Icon(Icons.search, color: cs.onSurfaceVariant),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        ),
      ),
    );
  }

  Widget _buildContinueLearning(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return LuminaCard(
      borderColor: cs.outlineVariant,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 120.w,
            height: 100.h,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.play_circle_outline, size: 40, color: cs.primary.withAlpha(150)),
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                  decoration: BoxDecoration(
                    color: LuminaColors.academicTeal.withAlpha(40),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'VIDEO LESSON',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: LuminaColors.academicTeal,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  'Fundamentals of Organic Chemistry',
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                    height: 1.2,
                  ),
                ),
                SizedBox(height: 12.h),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: 0.65,
                          minHeight: 6.h,
                          backgroundColor: cs.surfaceContainerHighest,
                          valueColor: const AlwaysStoppedAnimation<Color>(LuminaColors.academicTeal),
                        ),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      '65%',
                      style: TextStyle(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Local Storage',
              style: TextStyle(
                fontSize: 20.sp,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            Text(
              _totalCapacityStr,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: LuminaColors.academicTeal,
              ),
            ),
          ],
        ),
        SizedBox(height: 12.h),
        LuminaCard(
          padding: EdgeInsets.all(16.w),
          borderColor: cs.outlineVariant,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _totalStorageUsedStr,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  Text(
                    'Available on Device',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12.h),
              _buildMultiColorBar(12.h),
              _buildStorageLegend(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCategories(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Subject Categories',
              style: TextStyle(
                fontSize: 20.sp,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            GestureDetector(
              onTap: () {},
              child: Row(
                children: [
                  Text(
                    'View All',
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: LuminaColors.academicTeal,
                    ),
                  ),
                  SizedBox(width: 4.w),
                  Icon(Icons.arrow_forward, size: 14.sp, color: LuminaColors.academicTeal),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 12.h),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8.w,
            mainAxisSpacing: 8.w,
            childAspectRatio: 1.0,
          ),
          itemCount: _subjectCategories.length,
          itemBuilder: (context, index) {
            final cat = _subjectCategories[index];
            return _SubjectCategoryCard(
              label: cat.$1,
              icon: cat.$2,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ResourceListPage(type: cat.$3, title: cat.$1),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildRecentlyOpened(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recently Opened',
          style: TextStyle(
            fontSize: 20.sp,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        SizedBox(height: 12.h),
        Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: cs.outlineVariant, width: 1),
          ),
          child: ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _recentFiles.length,
            prototypeItem: _recentFiles.isNotEmpty ? _buildRecentFileItem(context, _recentFiles.first) : null,
            itemBuilder: (context, index) {
              return _buildRecentFileItem(context, _recentFiles[index]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRecentFileItem(BuildContext context, _RecentFile file) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () {},
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Icon(file.icon, size: 28.sp, color: file.color),
            SizedBox(width: 16.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    '${file.type} • ${file.time}',
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18.sp, color: cs.outline),
          ],
        ),
      ),
    );
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => LuminaSettingsSheet(
        onManageStorage: () => _showOfflineStorage(context),
      ),
    );
  }

  void _showOfflineStorage(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.storage, size: 20.sp, color: Theme.of(context).colorScheme.primary),
                  SizedBox(width: 8.w),
                  Text(
                    'Offline Storage',
                    style: TextStyle(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_totalStorageUsedStr,
                      style: TextStyle(fontSize: 12.sp, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  Text(_totalCapacityStr,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: LuminaColors.academicTeal)),
                ],
              ),
              SizedBox(height: 8.h),
              _buildMultiColorBar(16.h),
              _buildStorageLegend(),
              SizedBox(height: 24.h),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: LuminaColors.academicTeal),
                    foregroundColor: LuminaColors.academicTeal,
                    minimumSize: const Size(48, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: const Text('Close'),
                ),
              ),
              SizedBox(height: 8.h),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMultiColorBar(double minHeight) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: minHeight,
        child: Row(
          children: [
            Flexible(flex: _appFlex, child: Container(color: LuminaColors.academicTeal)),
            Flexible(flex: _otherFlex, child: Container(color: LuminaColors.saffron)),
            Flexible(flex: _freeFlex, child: Container(color: Theme.of(context).colorScheme.surfaceContainerHighest)),
          ],
        ),
      ),
    );
  }

  Widget _buildStorageLegend() {
    return Padding(
      padding: EdgeInsets.only(top: 16.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildLegendItem(LuminaColors.academicTeal, 'EduMesh', _appUsedStr),
          _buildLegendItem(LuminaColors.saffron, 'Other Apps', _otherUsedStr),
          _buildLegendItem(Theme.of(context).colorScheme.outline, 'Free', _freeRemainingStr),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8.w, height: 8.w, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        SizedBox(width: 6.w),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 10.sp, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
            Text(value, style: TextStyle(fontSize: 11.sp, color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }
}

class _SubjectCategoryCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _SubjectCategoryCard({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant, width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28.sp, color: cs.primary),
            SizedBox(height: 8.h),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentFile {
  final String title;
  final String type;
  final String time;
  final IconData icon;
  final Color color;
  final ResourceType resourceType;

  _RecentFile({
    required this.title,
    required this.type,
    required this.time,
    required this.icon,
    required this.color,
    required this.resourceType,
  });
}
