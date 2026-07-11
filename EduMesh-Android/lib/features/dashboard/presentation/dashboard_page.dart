import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/constants/lumina_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/services/connectivity_service.dart';
import '../../../core/storage/db_helper.dart';
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



  String _totalStorageUsedStr = 'Calculating...';
  String _totalCapacityStr = 'Calculating...';
  String _appUsedStr = 'Calculating...';
  String _otherUsedStr = 'Calculating...';
  String _freeRemainingStr = 'Calculating...';

  int _appFlex = 1;
  int _otherFlex = 1;
  int _freeFlex = 1;

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
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkServer() async {
    final connected = await ConnectivityService().ping(timeout: const Duration(seconds: 10));
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
      const apkSize = 65 * 1024 * 1024;
      final appUsedBytes = appDataSize + apkSize;
      const totalBytes = 128 * 1024 * 1024 * 1024; // ponytail: hardcoded, was MethodChannel
      const availableBytes = 64 * 1024 * 1024 * 1024;
      final otherUsedBytes = (totalBytes - availableBytes - appUsedBytes).clamp(0, totalBytes);

      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          final appMb = appUsedBytes / (1024 * 1024);
          _appUsedStr = appMb < 1024 ? '${appMb.toStringAsFixed(1)}${l10n.unitMegabytes}' : '${(appMb / 1024).toStringAsFixed(1)}${l10n.unitGigabytes}';
          final otherGb = otherUsedBytes / (1024 * 1024 * 1024);
          _otherUsedStr = otherGb < 1.0 ? '${(otherUsedBytes / (1024 * 1024)).toStringAsFixed(1)}${l10n.unitMegabytes}' : '${otherGb.toStringAsFixed(1)}${l10n.unitGigabytes}';
          _freeRemainingStr = '${(availableBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}${l10n.unitGigabytes}';
          _totalCapacityStr = l10n.storageTotalCapacity((totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(0));
          _appFlex = (appUsedBytes / totalBytes * 1000).toInt().clamp(1, 1000);
          _otherFlex = (otherUsedBytes / totalBytes * 1000).toInt().clamp(1, 1000);
          _freeFlex = (availableBytes / totalBytes * 1000).toInt().clamp(1, 1000);
          _totalStorageUsedStr = l10n.storageUsedLabel(((appUsedBytes + otherUsedBytes) / (1024 * 1024 * 1024)).toStringAsFixed(1));
        });
      }
    } catch (e) {
      if (mounted) { final l10n = AppLocalizations.of(context)!; setState(() => _appUsedStr = _otherUsedStr = _freeRemainingStr = l10n.storageUnknown); }
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
      final db = DBHelper();
        final bookmarks = await db.getBookmarkedResources();
        final downloads = await db.getDownloadedResources();
        final subjectsSet = <String>{};
        for (final r in bookmarks) {
          final s = r['subject'] as String? ?? '';
          if (s.isNotEmpty) subjectsSet.add(s);
        }
        for (final r in downloads) {
          final s = r['subject'] as String? ?? '';
          if (s.isNotEmpty) subjectsSet.add(s);
        }
        final local = subjectsSet.map((s) => {'name': s}).toList();
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
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w, vertical: AppSpacing.sm.h),
      decoration: BoxDecoration(color: cs.surface, border: Border(bottom: BorderSide(color: cs.outlineVariant))),
      child: Row(
        children: [
                  Icon(Icons.school, color: cs.primary, size: 24.sp),
          SizedBox(width: AppSpacing.md.w),
          Text(l10n.appTitle, style: tt.titleLarge?.copyWith(fontWeight: AppSpacing.weightDisplay, color: cs.primary)),
          const Spacer(),
          _buildServerStatusBadge(),
          SizedBox(width: AppSpacing.sm.w),
          Semantics(button: true, label: l10n.semanticsSettings, child: GestureDetector(onTap: () => _showSettings(context), child: Icon(Icons.settings, color: cs.primary, size: 24.sp))),
        ],
      ),
    );
  }

  Widget _buildServerStatusBadge() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    Color bgColor = _isChecking ? cs.surfaceContainerHighest.withAlpha(128) : (_isConnected ? cs.secondaryContainer : cs.errorContainer);
    Color textColor = _isChecking ? cs.outline : (_isConnected ? cs.onSecondaryContainer : cs.onErrorContainer);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm.w, vertical: AppSpacing.xs.h),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(AppSpacing.radiusFull), border: Border.all(color: textColor)),
      child: Text(_isChecking ? l10n.serverStatusChecking : (_isConnected ? l10n.serverStatusConnected : l10n.serverStatusDisconnected), style: tt.bodySmall?.copyWith(color: textColor)),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      button: true,
      label: l10n.semanticsSearchResources,
      child: GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchPage())),
      child: Container(
        margin: EdgeInsets.only(top: AppSpacing.lg.h),
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w, vertical: AppSpacing.md.h),
        decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(AppSpacing.radiusSm.r)),
        child: Row(
          children: [
            Icon(Icons.search_rounded, color: cs.onSurfaceVariant, size: 22.sp),
            SizedBox(width: AppSpacing.md.w),
            Expanded(child: Text(l10n.searchBarHint, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant))),
            Semantics(
              button: true,
              label: l10n.semanticsFilterResources,
              child: GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => SearchPage(initialGrade: _myGrade ?? '', openFilters: true),
              )),
              child: Icon(Icons.tune_rounded, color: cs.primary, size: 20.sp),
            ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildRecentlyViewedSection(BuildContext context) {
    return const SizedBox.shrink();
  }

  Widget _buildCategories(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.sectionSubjects, style: tt.titleLarge?.copyWith(fontWeight: AppSpacing.weightDisplay, color: cs.onSurface)),
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
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            ),
          )
        else
          Wrap(
            spacing: AppSpacing.sm.w,
            runSpacing: AppSpacing.sm.h,
            children: _subjects.map((sub) {
              final name = sub['name'] as String;
              return ActionChip(
                label: Text(name, style: tt.titleSmall?.copyWith(color: cs.onSurface)),
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
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.sectionLocalStorage, style: tt.titleLarge?.copyWith(fontWeight: AppSpacing.weightDisplay, color: cs.onSurface)),
        SizedBox(height: AppSpacing.md.h),
        Card(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.lg.w),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_totalStorageUsedStr != 'Calculating...') ...[
                Text(_totalStorageUsedStr, style: tt.titleSmall?.copyWith(color: cs.onSurface)),
                SizedBox(height: AppSpacing.xs.h),
                Text(_totalCapacityStr, style: tt.bodySmall?.copyWith(fontWeight: AppSpacing.weightDisplay, color: LuminaColors.academicTeal)),
                SizedBox(height: AppSpacing.md.h),
              ],
              _buildMultiColorBar(AppSpacing.md.h),
              _buildStorageLegend(),
            ],
          ),
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
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.md.w, vertical: AppSpacing.sm.h),
      decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(AppSpacing.radiusMd.r), border: Border.all(color: cs.outlineVariant)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Container(width: AppSpacing.sm.w, height: AppSpacing.sm.w, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), SizedBox(width: AppSpacing.sm.w), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: tt.labelSmall?.copyWith(fontSize: 10.sp, color: cs.onSurfaceVariant)), SizedBox(height: AppSpacing.xs.h), Text(value, style: tt.labelSmall?.copyWith(fontWeight: AppSpacing.weightStrong, color: cs.onSurface))])]),
    );
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusLg))), builder: (_) => const LuminaSettingsSheet());
  }

}

