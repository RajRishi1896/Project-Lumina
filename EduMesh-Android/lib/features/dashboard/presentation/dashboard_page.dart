import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/lumina_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/services/connectivity_service.dart';
import '../../../core/storage/db_helper.dart';
import '../../../shared/widgets/lumina_settings_sheet.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';
import 'resource_detail_page.dart';
import 'subject_topics_page.dart';
import 'kiwix_view.dart';
import '../../../core/services/recent_resources.dart';

/// The main dashboard page displayed after login.
///
/// Shows a search bar, recently-viewed resources, subject category grid, and a
/// local storage usage section. Periodically pings the server to display
/// connection status.
class DashboardPage extends StatefulWidget {
  /// Called when the user taps the search bar -- switch to Browse tab.
  final VoidCallback? onBrowseTap;
  const DashboardPage({super.key, this.onBrowseTap});

  /// Creates the state for the [DashboardPage].
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _isConnected = false;
  bool _isChecking = true;
  Timer? _pingTimer;



  String _totalStorageUsedStr = '';
  String _totalCapacityStr = '';
  String _appUsedStr = '';
  String _otherUsedStr = '';
  String _freeRemainingStr = '';

  int _appFlex = 1;
  int _otherFlex = 1;
  int _freeFlex = 1;

  List<Map<String, dynamic>> _subjects = [];
  bool _subjectsLoading = true;

  List<Map<String, String>> _recentResources = [];

  @override
  void initState() {
    super.initState();
    _checkServer();
    _pingTimer = Timer.periodic(const Duration(seconds: 60), (_) => _checkServer());
    _calcTotalStorage();
    _loadSubjects();
    _loadRecentResources();
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkServer() async {
    final connected = await ConnectivityService().ping();
    if (mounted) {
      setState(() {
        _isConnected = connected;
        _isChecking = false;
      });
    }
  }

  Future<void> _calcTotalStorage() async {
    // ponytail: use cached app size from SharedPreferences, compute in background.
    // Recursive dir listing on eMMC takes 0.5-2s and blocks first render.
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedSize = prefs.getInt('cached_app_size_bytes');
      if (cachedSize != null && cachedSize > 0) {
        _applyStorageValues(cachedSize);
        // Re-compute in background and cache for next time
        unawaited(_computeAndCacheStorage());
        return;
      }
    } catch (_) {}
    await _computeAndCacheStorage();
  }

  Future<void> _computeAndCacheStorage() async {
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
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('cached_app_size_bytes', appUsedBytes);
      } catch (_) {}
      _applyStorageValues(appUsedBytes);
    } catch (e) {
      if (mounted) { final l10n = AppLocalizations.of(context)!; setState(() => _appUsedStr = _otherUsedStr = _freeRemainingStr = l10n.storageUnknown); }
    }
  }

  void _applyStorageValues(int appUsedBytes) {
      const totalBytes = 128 * 1024 * 1024 * 1024;
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
  }

  Future<void> _loadSubjects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getStringList('cached_subjects');
      if (cached != null && cached.isNotEmpty) {
        _subjects = cached.map((s) {
          final parts = s.split('|');
          return {'name': parts[0], if (parts.length > 1) 'symbol': parts[1]};
        }).toList();
        _subjectsLoading = false;
        if (mounted) setState(() {});
      }

      final response = await ApiClient.get('/student/subjects');
      if (mounted && response.statusCode == 200 && response.data is List) {
        final raw = (response.data as List).whereType<Map<String, dynamic>>().toList();
        final names = raw.map((s) {
          final name = s['name']?.toString() ?? '';
          final symbol = s['symbol']?.toString() ?? '';
          return '$name|$symbol';
        }).toList();
        await prefs.setStringList('cached_subjects', names);
        setState(() {
          _subjects = raw;
          _subjectsLoading = false;
        });
        return;
      }
    } catch (_) { } try {
      if (_subjects.isEmpty) {
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
        if (mounted && local.isNotEmpty) {
          setState(() {
            _subjects = local;
            _subjectsLoading = false;
          });
        }
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
                  SizedBox(height: AppSpacing.xxl.h),
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
          SvgPicture.asset(
            Theme.of(context).brightness == Brightness.dark ? 'assets/images/logo-light.svg' : 'assets/images/logo-dark.svg',
            width: 28.sp,
            height: 28.sp,
          ),
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
      onTap: widget.onBrowseTap,
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
              onTap: widget.onBrowseTap,
              child: Icon(Icons.tune_rounded, color: cs.primary, size: 20.sp),
            ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Future<void> _loadRecentResources() async {
    try {
      final resources = await RecentResources.load();
      if (mounted) setState(() => _recentResources = resources);
    } catch (_) {}
  }

  Future<void> _openRecentKiwix(Map<String, String> r) async {
    final id = r['id'] ?? '';
    if (id.isEmpty) return;
    try {
      final resp = await ApiClient.get('/zim/page', queryParameters: {'article_id': id})
          .timeout(const Duration(seconds: 8));
      final html = resp.data?['html']?.toString();
      if (!mounted || html == null || html.isEmpty) return;
      unawaited(Navigator.push(context, MaterialPageRoute(
        builder: (_) => KiwixView(initialHtml: html, title: r['title'] ?? '', baseUrl: ApiClient.baseUrl),
      )).then((_) => _loadRecentResources()));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.zimArticleNotFound)));
    }
  }

  Widget _buildRecentlyViewedSection(BuildContext context) {
    if (_recentResources.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.sectionRecentlyAccessed, style: tt.titleLarge?.copyWith(fontWeight: AppSpacing.weightDisplay, color: cs.onSurface)),
        SizedBox(height: AppSpacing.md.h),
        SizedBox(
          height: 80.h,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _recentResources.length,
            separatorBuilder: (_, __) => SizedBox(width: AppSpacing.sm.w),
            itemBuilder: (context, index) {
              final r = _recentResources[index];
              final type = r['type'] ?? '';
              final icon = _iconForResourceType(type);
              return GestureDetector(
                onTap: () {
                  if (type == 'kiwix') {
                    _openRecentKiwix(r);
                  } else {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ResourceDetailPage(
                        title: r['title'] ?? '',
                        subject: '',
                        grade: '',
                        resourceType: type,
                        resourceId: r['id'],
                      ),
                    )).then((_) => _loadRecentResources());
                  }
                },
                child: Container(
                  width: 120.w,
                  padding: EdgeInsets.all(AppSpacing.md.w),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm.r),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 24.sp, color: cs.primary),
                      SizedBox(height: AppSpacing.xs.h),
                      Text(r['title'] ?? '', style: tt.labelSmall?.copyWith(color: cs.onSurface),
                        maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  IconData _iconForResourceType(String type) {
    switch (type) {
      case 'textbook': return Icons.menu_book_outlined;
      case 'videos': return Icons.play_circle_outline;
      case 'pyq': return Icons.quiz_outlined;
      case 'pastPaper': return Icons.description_outlined;
      case 'kiwix': return Icons.language_outlined;
      case 'quiz': return Icons.fact_check_outlined;
      case 'notes': return Icons.note_alt_outlined;
      default: return Icons.article_outlined;
    }
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
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 400 ? 3 : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _subjects.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: AppSpacing.sm.w,
                  mainAxisSpacing: AppSpacing.sm.h,
                  childAspectRatio: 1.1,
                ),
                itemBuilder: (context, index) {
                  final name = _subjects[index]['name'] as String? ?? '';
                  return GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => SubjectTopicsPage(subject: name),
                    )),
                    child: Container(
                      padding: EdgeInsets.all(AppSpacing.md.w),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusSm.r),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 48.w,
                            height: 48.w,
                            decoration: BoxDecoration(
                              color: cs.primary.withAlpha(31),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(_iconForSubject(name), color: cs.primary, size: 24.sp),
                          ),
                          SizedBox(height: AppSpacing.sm.h),
                          Text(name, style: tt.labelSmall?.copyWith(color: cs.onSurface),
                            maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
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
              if (_totalStorageUsedStr.isNotEmpty) ...[
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

  IconData _iconForSubject(String name) {
    final n = name.toLowerCase();
    if (n.contains('math')) return Icons.calculate_outlined;
    if (n.contains('com') || n.contains('tech')) return Icons.computer_outlined;
    if (n.contains('sci') || n.contains('chem')) return Icons.science_outlined;
    if (n.contains('phy')) return Icons.bolt_outlined;
    if (n.contains('bio')) return Icons.biotech_outlined;
    if (n.contains('eng') || n.contains('hin') || n.contains('kan') ||
        n.contains('tam') || n.contains('tel') || n.contains('fra') || n.contains('fre')) {
      return Icons.abc_outlined;
    }
    if (n.contains('his')) return Icons.history_edu_outlined;
    if (n.contains('geo') || n.contains('soc')) return Icons.public_outlined;
    if (n.contains('civ')) return Icons.account_balance_outlined;
    if (n.contains('eco')) return Icons.trending_up_outlined;
    return Icons.menu_book_outlined;
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusLg))), builder: (_) => const LuminaSettingsSheet());
  }

}

