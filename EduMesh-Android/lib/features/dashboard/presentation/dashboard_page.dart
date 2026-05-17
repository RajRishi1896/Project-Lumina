import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/constants/lumina_colors.dart';
import '../../../core/models/resource_model.dart';
import '../../../core/services/storage_service.dart';
import '../../../shared/widgets/lumina_card.dart';
import '../../../shared/widgets/lumina_settings_sheet.dart';
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
      final totalUsedBytes = appDataSize + apkSize;
      
      final storageInfo = await _storageService.getStorageInfo();
      final totalBytes = storageInfo['totalBytes'] ?? (128 * 1024 * 1024 * 1024);
      
      if (mounted) {
        setState(() {
          final usedMb = totalUsedBytes / (1024 * 1024);
          if (usedMb < 1024) {
            _totalStorageUsedStr = '${usedMb.toStringAsFixed(1)} MB used';
          } else {
            _totalStorageUsedStr = '${(usedMb / 1024).toStringAsFixed(1)} GB used';
          }
          
          final totalGb = totalBytes / (1024 * 1024 * 1024);
          _totalCapacityStr = '${totalGb.toStringAsFixed(0)} GB Total';
          
          _totalStorageProgress = (totalUsedBytes / totalBytes).clamp(0.0, 1.0);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _totalStorageUsedStr = 'Unknown');
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
            _buildBottomNav(),
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
                    ? 'Local Server: Connected'
                    : 'Local Server: Disconnected'),
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
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _totalStorageProgress,
                  minHeight: 12.h,
                  backgroundColor: cs.surfaceContainerHighest,
                  valueColor: const AlwaysStoppedAnimation<Color>(LuminaColors.academicTeal),
                ),
              ),
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
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _totalStorageProgress,
                  minHeight: 16.h,
                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  valueColor: const AlwaysStoppedAnimation<Color>(LuminaColors.academicTeal),
                ),
              ),
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

  Widget _buildBottomNav() {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(Icons.dashboard, 'Portal', true),
          _buildNavItem(Icons.menu_book, 'Subjects', false),
          _buildNavItem(Icons.download_for_offline, 'Saved', false),
          _buildNavItem(Icons.person, 'Profile', false),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, bool active) {
    final color = active ? LuminaColors.academicTeal : Colors.grey.shade400;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 24.sp),
        SizedBox(height: 4.h),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.sp,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            color: color,
          ),
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
