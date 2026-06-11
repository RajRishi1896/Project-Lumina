import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/constants/lumina_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/connection_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/services/recent_files_service.dart';
import '../../../shared/services/save_resource_service.dart';
import '../../../shared/widgets/lumina_card.dart';
import '../../../shared/widgets/lumina_settings_sheet.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';
import '../../auth/data/auth_service.dart';
import 'search_page.dart';
import 'resource_page.dart';

/// The main dashboard page displayed after login.
///
/// Shows a search bar, recently-viewed resources, subject category grid, and a
/// local storage usage section. Periodically pings the server to display
/// connection status.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  /// Creates the state for the [DashboardPage].
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _isConnected = false;
  bool _isChecking = true;
  Timer? _pingTimer;
  final ConnectionService _connectionService = ConnectionService();
  
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

  String? _myGrade;

  List<Map<String, dynamic>> _subjects = [];
  bool _subjectsLoading = true;

  @override
  void initState() {
    super.initState();
    _checkServer();
    _pingTimer = Timer.periodic(const Duration(seconds: 60), (_) => _checkServer());
    _calcTotalStorage();
    _loadSubjects();
    AuthService().getStudentGrade().then((g) { if (mounted) setState(() => _myGrade = g); });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recentService.addListener(_updateUI);
    });
  }
  void _updateUI() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _recentService.removeListener(_updateUI);
    super.dispose();
  }

  Future<void> _checkServer() async {
    final connected = await _connectionService.ping(timeout: const Duration(seconds: 10));
    if (mounted) {
      setState(() {
        _isConnected = connected;
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
      var totalBytes = (storageInfo['totalBytes'] ?? (128 * 1024 * 1024 * 1024)) as num;
      if (totalBytes == 0) totalBytes = 128 * 1024 * 1024 * 1024;
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

  Future<void> _loadSubjects() async {
    try {
      final response = await ApiClient.get('/subjects');
      if (mounted && response.statusCode == 200 && response.data is List) {
        setState(() {
          _subjects = (response.data as List).cast<Map<String, dynamic>>();
          _subjectsLoading = false;
        });
        return;
      }
    } catch (_) { } try {
      final local = await SaveResourceService.getDistinctSubjects();
      if (mounted) {
        setState(() {
          _subjects = local;
          _subjectsLoading = false;
        });
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
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w),
                children: [
                  _buildSearchBar(context),
                  SizedBox(height: AppSpacing.xxl.h),
                  _buildRecentlyViewedSection(context),
                  if (_recentService.recentFiles.isNotEmpty) SizedBox(height: AppSpacing.xxl.h),
                  _buildCategories(context),
                  SizedBox(height: AppSpacing.xxl.h),
                  _buildStorageSection(context),
                  SizedBox(height: AppSpacing.xxl.h),
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
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w, vertical: AppSpacing.sm.h),
      decoration: BoxDecoration(color: cs.surface, border: Border(bottom: BorderSide(color: cs.outlineVariant, width: 1))),
      child: Row(
        children: [
                  Icon(Icons.school, color: cs.primary, size: 24.sp),
          SizedBox(width: AppSpacing.md.w),
          Text(l10n.appTitle, style: TextStyle(fontSize: 20.sp, fontWeight: AppSpacing.weightDisplay, color: cs.primary)),
          const Spacer(),
          _buildServerStatusBadge(),
          SizedBox(width: AppSpacing.sm.w),
          GestureDetector(onTap: () => _showSettings(context), child: Icon(Icons.settings, color: cs.primary, size: 24.sp)),
        ],
      ),
    );
  }

  Widget _buildServerStatusBadge() {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    Color bgColor = _isChecking ? cs.surfaceContainerHighest.withAlpha(128) : (_isConnected ? cs.secondaryContainer : cs.errorContainer);
    Color textColor = _isChecking ? cs.outline : (_isConnected ? cs.onSecondaryContainer : cs.onErrorContainer);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm.w, vertical: AppSpacing.xs.h),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(AppSpacing.radiusFull), border: Border.all(color: textColor, width: 1)),
      child: Text(_isChecking ? l10n.serverStatusChecking : (_isConnected ? l10n.serverStatusConnected : l10n.serverStatusDisconnected), style: TextStyle(fontSize: 12.sp, fontWeight: AppSpacing.weightBody, color: textColor)),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchPage())),
      child: Container(
        margin: EdgeInsets.only(top: AppSpacing.lg.h),
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w, vertical: AppSpacing.md.h),
        decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(AppSpacing.radiusSm.r)),
        child: Row(
          children: [
            Icon(Icons.search_rounded, color: cs.onSurfaceVariant, size: 22.sp),
            SizedBox(width: AppSpacing.md.w),
            Expanded(child: Text(l10n.searchBarHint, style: TextStyle(fontSize: 14.sp, color: cs.onSurfaceVariant, fontWeight: AppSpacing.weightBody))),
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => SearchPage(initialGrade: _myGrade ?? '', openFilters: true),
              )),
              child: Icon(Icons.tune_rounded, color: cs.primary, size: 20.sp),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentlyViewedSection(BuildContext context) {
    final recentFiles = _recentService.recentFiles;
    if (recentFiles.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.sectionRecentlyViewed, style: TextStyle(fontSize: 20.sp, fontWeight: AppSpacing.weightDisplay, color: cs.onSurface)),
        SizedBox(height: AppSpacing.md.h),
        SizedBox(
          height: 130.h,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w),
            itemCount: recentFiles.length,
            separatorBuilder: (_, __) => SizedBox(width: AppSpacing.md.w),
            itemBuilder: (context, index) {
              final file = recentFiles[index];
              return Container(
                width: 150.w,
                padding: EdgeInsets.all(AppSpacing.md.w),
                decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(AppSpacing.radiusLg.r), border: Border.all(color: cs.outlineVariant)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(file.icon, color: file.color, size: 24.sp),
                    SizedBox(height: AppSpacing.sm.h),
                    Text(file.title, style: TextStyle(fontSize: 12.sp, fontWeight: AppSpacing.weightStrong), maxLines: 1, overflow: TextOverflow.ellipsis),
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
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.sectionSubjects, style: TextStyle(fontSize: 20.sp, fontWeight: AppSpacing.weightDisplay, color: cs.onSurface)),
        SizedBox(height: AppSpacing.md.h),
        if (_subjectsLoading && _subjects.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.section.h),
            child: Center(child: CircularProgressIndicator(strokeWidth: 3.w)),
          )
        else if (!_subjectsLoading && _subjects.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.section.h),
            child: Center(
              child: Text(l10n.sectionSubjectsEmpty,
                  style: TextStyle(fontSize: 14.sp, color: cs.onSurfaceVariant)),
            ),
          )
        else
          Wrap(
            spacing: AppSpacing.sm.w,
            runSpacing: AppSpacing.sm.h,
            children: _subjects.map((sub) {
              final name = sub['name'] as String;
              return ActionChip(
                label: Text(name, style: TextStyle(fontSize: 13.sp, fontWeight: AppSpacing.weightStrong, color: cs.onSurface)),
                onPressed: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ResourcePage(subject: name, grade: _myGrade ?? ''),
                )),
                backgroundColor: cs.surfaceContainerHighest,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusSm.r)),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildStorageSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.sectionLocalStorage, style: TextStyle(fontSize: 20.sp, fontWeight: AppSpacing.weightDisplay, color: cs.onSurface)),
        SizedBox(height: AppSpacing.md.h),
        LuminaCard(
          padding: EdgeInsets.all(AppSpacing.lg.w),
          borderColor: cs.outlineVariant,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_totalStorageUsedStr != 'Calculating...') ...[
                Text(_totalStorageUsedStr, style: TextStyle(fontSize: 14.sp, fontWeight: AppSpacing.weightStrong, color: cs.onSurface)),
                SizedBox(height: AppSpacing.xs.h),
                Text(_totalCapacityStr, style: TextStyle(fontSize: 12.sp, fontWeight: AppSpacing.weightDisplay, color: LuminaColors.academicTeal)),
                SizedBox(height: AppSpacing.md.h),
              ],
              _buildMultiColorBar(AppSpacing.md.h),
              _buildStorageLegend(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMultiColorBar(double minHeight) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(height: minHeight, child: Row(children: [Flexible(flex: _appFlex, child: Container(color: LuminaColors.academicTeal)), Flexible(flex: _otherFlex, child: Container(color: LuminaColors.saffron)), Flexible(flex: _freeFlex, child: Container(color: cs.outlineVariant))])),
    );
  }

  Widget _buildStorageLegend() {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.only(top: AppSpacing.lg.h),
      child: Wrap(spacing: AppSpacing.md.w, runSpacing: AppSpacing.md.h, children: [_buildLegendItem(LuminaColors.academicTeal, l10n.storageLegendAppLabel, _appUsedStr), _buildLegendItem(LuminaColors.saffron, l10n.storageLegendOtherLabel, _otherUsedStr), _buildLegendItem(cs.outlineVariant, l10n.storageLegendFreeLabel, _freeRemainingStr)]),
    );
  }

  Widget _buildLegendItem(Color color, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.md.w, vertical: AppSpacing.sm.h),
      decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(AppSpacing.radiusMd.r), border: Border.all(color: cs.outlineVariant)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Container(width: AppSpacing.sm.w, height: AppSpacing.sm.w, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), SizedBox(width: AppSpacing.sm.w), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: TextStyle(fontSize: 10.sp, fontWeight: AppSpacing.weightBody, color: cs.onSurfaceVariant)), SizedBox(height: AppSpacing.xs.h), Text(value, style: TextStyle(fontSize: 11.sp, fontWeight: AppSpacing.weightStrong, color: cs.onSurface))])]),
    );
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet(context: context, isScrollControlled: true, shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusLg))), builder: (_) => const LuminaSettingsSheet());
  }

}

