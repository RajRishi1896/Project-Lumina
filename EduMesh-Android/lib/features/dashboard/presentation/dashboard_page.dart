import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/constants/lumina_colors.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/services/recent_files_service.dart'; // Ensure this import is correct
import '../../../shared/widgets/lumina_card.dart';
import '../../../shared/widgets/lumina_settings_sheet.dart';
import '../../auth/data/auth_service.dart';
import 'grade_page.dart';
import 'search_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _isConnected = false;
  bool _isChecking = true;
  
  // Use the Service for Recent Files
  final RecentFilesService _recentService = RecentFilesService();

  String _totalStorageUsedStr = 'Calculating...';
  String _totalCapacityStr = 'Calculating...';
  String _appUsedStr = 'Calculating...';
  String _otherUsedStr = 'Calculating...';
  String _freeRemainingStr = 'Calculating...';

  int _appFlex = 1;
  int _otherFlex = 1;
  int _freeFlex = 1;

  final StorageService _storageService = StorageService();

  List<Map<String, dynamic>> _subjects = [];
  bool _subjectsLoading = true;

  @override
  void initState() {
    super.initState();
    _checkServer();
    _calcTotalStorage();
    _loadSubjects();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recentService.addListener(_updateUI);
    });
  }
  void _updateUI() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _recentService.removeListener(_updateUI);
    super.dispose();
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
          if (entity is File) appDataSize += await entity.length();
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
          final appMb = appUsedBytes / (1024 * 1024);
          _appUsedStr = appMb < 1024 ? '${appMb.toStringAsFixed(1)} MB' : '${(appMb / 1024).toStringAsFixed(1)} GB';
          final otherGb = otherUsedBytes / (1024 * 1024 * 1024);
          _otherUsedStr = otherGb < 1.0 ? '${(otherUsedBytes / (1024 * 1024)).toStringAsFixed(1)} MB' : '${otherGb.toStringAsFixed(1)} GB';
          _freeRemainingStr = '${(availableBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
          _totalCapacityStr = '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(0)} GB Total';
          _appFlex = (appUsedBytes / totalBytes * 1000).toInt().clamp(1, 1000);
          _otherFlex = (otherUsedBytes / totalBytes * 1000).toInt().clamp(1, 1000);
          _freeFlex = (availableBytes / totalBytes * 1000).toInt().clamp(1, 1000);
          _totalStorageUsedStr = '${((appUsedBytes + otherUsedBytes) / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB used';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _appUsedStr = _otherUsedStr = _freeRemainingStr = 'Unknown');
    }
  }

  IconData _iconForSubject(String name) {
    const iconMap = {
      'Mathematics': Icons.calculate,
      'Science': Icons.biotech,
      'History': Icons.history_edu,
      'Literature': Icons.translate,
      'English': Icons.translate,
      'Computer Science': Icons.computer,
      'Physics': Icons.science,
      'Chemistry': Icons.science,
      'Biology': Icons.biotech,
      'General': Icons.folder,
    };
    return iconMap[name] ?? Icons.book;
  }

  Future<void> _loadSubjects() async {
    try {
      final response = await ApiClient.get('/subjects');
      if (mounted && response.statusCode == 200 && response.data is List) {
        setState(() {
          _subjects = (response.data as List).cast<Map<String, dynamic>>();
          _subjectsLoading = false;
        });
      } else if (mounted) {
        setState(() => _subjectsLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _subjectsLoading = false);
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
                  _buildRecentlyViewedSection(context),
                  if (_recentService.recentFiles.isNotEmpty) SizedBox(height: 24.h),
                  _buildCategories(context),
                  SizedBox(height: 24.h),
                  _buildStorageSection(context),
                  SizedBox(height: 24.h),
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
      decoration: BoxDecoration(color: cs.surface, border: Border(bottom: BorderSide(color: cs.outlineVariant, width: 1))),
      child: Row(
        children: [
                  Icon(Icons.school, color: cs.primary, size: 24.sp), // App icon
          SizedBox(width: 12.w),
          Text('Project Lumina', style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700, color: cs.primary)),
          const Spacer(),
          _buildServerStatusBadge(),
          SizedBox(width: 8.w),
          GestureDetector(onTap: () => _showSettings(context), child: Icon(Icons.settings, color: cs.primary, size: 24.sp)),
        ],
      ),
    );
  }

  Widget _buildServerStatusBadge() {
    final cs = Theme.of(context).colorScheme;
    Color bgColor = _isChecking ? cs.surfaceContainerHighest.withAlpha(128) : (_isConnected ? cs.secondaryContainer : cs.errorContainer);
    Color textColor = _isChecking ? cs.outline : (_isConnected ? cs.onSecondaryContainer : cs.onErrorContainer);
    Color dotColor = _isChecking ? cs.outline : (_isConnected ? const Color(0xFF16A34A) : const Color(0xFFDC2626));

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(100), border: Border.all(color: textColor, width: 1)),
      child: Row(
        children: [
          Container(width: 8.w, height: 8.w, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
          SizedBox(width: 6.w),
          Text(_isChecking ? 'Checking...' : (_isConnected ? 'Connected' : 'Disconnected'), style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: textColor)),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchPage())),
      child: Container(
        margin: EdgeInsets.only(top: 16.h),
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(16.r), border: Border.all(color: cs.outlineVariant), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))]),
        child: Row(
          children: [
            Icon(Icons.search_rounded, color: cs.onSurfaceVariant, size: 22.sp),
            SizedBox(width: 12.w),
            Expanded(child: Text('Search all resources...', style: TextStyle(fontSize: 14.sp, color: cs.onSurfaceVariant, fontWeight: FontWeight.w500))),
            Icon(Icons.tune_rounded, color: cs.primary, size: 20.sp),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentlyViewedSection(BuildContext context) {
    final recentFiles = _recentService.recentFiles;
    if (recentFiles.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Recently Viewed", style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700, color: cs.onSurface)),
        SizedBox(height: 12.h),
        SizedBox(
          height: 130.h,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            itemCount: recentFiles.length,
            separatorBuilder: (_, __) => SizedBox(width: 12.w),
            itemBuilder: (context, index) {
              final file = recentFiles[index];
              return Container(
                width: 150.w,
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(16.r), border: Border.all(color: cs.outlineVariant)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(file.icon, color: file.color, size: 24.sp),
                    SizedBox(height: 8.h),
                    Text(file.title, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(file.time, style: TextStyle(fontSize: 10.sp, color: cs.onSurfaceVariant)),
                  ],
                ),
              );
            },
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
        Text('Subject Categories', style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700, color: cs.onSurface)),
        SizedBox(height: 12.h),
        if (_subjectsLoading && _subjects.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 32.h),
            child: Center(child: CircularProgressIndicator(strokeWidth: 3.w)),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12.w, mainAxisSpacing: 12.w, childAspectRatio: 1.2),
            itemCount: _subjects.length,
            itemBuilder: (context, index) {
              final sub = _subjects[index];
              return _SubjectCategoryCard(
                label: sub['name'] as String,
                icon: _iconForSubject(sub['name'] as String),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GradePage(subject: sub['name'] as String))),
              );
            },
          ),
      ],
    );
  }

  Widget _buildStorageSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Local Storage', style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700, color: cs.onSurface)),
        SizedBox(height: 12.h),
        LuminaCard(
          padding: EdgeInsets.all(16.w),
          borderColor: cs.outlineVariant,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Only show these if the calculation has finished
              if (_totalStorageUsedStr != 'Calculating...') ...[
                Text(_totalStorageUsedStr, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: cs.onSurface)),
                SizedBox(height: 4.h),
                Text(_totalCapacityStr, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: LuminaColors.academicTeal)),
                SizedBox(height: 12.h),
              ],
              
              // Always show the bar and legend
              _buildMultiColorBar(12.h),
              _buildStorageLegend(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMultiColorBar(double minHeight) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(height: minHeight, child: Row(children: [Flexible(flex: _appFlex, child: Container(color: LuminaColors.academicTeal)), Flexible(flex: _otherFlex, child: Container(color: LuminaColors.saffron)), Flexible(flex: _freeFlex, child: Container(color: Colors.grey))])),
    );
  }

  Widget _buildStorageLegend() {
    return Padding(
      padding: EdgeInsets.only(top: 16.h),
      child: Wrap(spacing: 12.w, runSpacing: 12.h, children: [_buildLegendItem(LuminaColors.academicTeal, 'EduMesh', _appUsedStr), _buildLegendItem(LuminaColors.saffron, 'Other Apps', _otherUsedStr), _buildLegendItem(Colors.grey, 'Free', _freeRemainingStr)]),
    );
  }

  Widget _buildLegendItem(Color color, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(14.r), border: Border.all(color: cs.outlineVariant)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 10.w, height: 10.w, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), SizedBox(width: 8.w), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)), SizedBox(height: 2.h), Text(value, style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.bold, color: cs.onSurface))])]),
    );
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))), builder: (_) => LuminaSettingsSheet(onManageStorage: () => _showOfflineStorage(context)));
  }

  void _showOfflineStorage(BuildContext context) {
    showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))), builder: (_) => SafeArea(child: Padding(padding: EdgeInsets.all(24.w), child: Column(mainAxisSize: MainAxisSize.min, children: [Text('Offline Storage', style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700)), SizedBox(height: 20.h), _buildMultiColorBar(16.h), _buildStorageLegend()]))));
  }
}

class _SubjectCategoryCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _SubjectCategoryCard({required this.label, required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(20.r), border: Border.all(color: cs.outlineVariant), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 3))]),
        padding: EdgeInsets.all(12.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(padding: EdgeInsets.all(12.w), decoration: BoxDecoration(color: LuminaColors.academicTeal.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16.r)), child: Icon(icon, color: LuminaColors.academicTeal, size: 28.sp)),
            SizedBox(height: 10.h),
            Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: cs.onSurface)),
          ],
        ),
      ),
    );
  }
}