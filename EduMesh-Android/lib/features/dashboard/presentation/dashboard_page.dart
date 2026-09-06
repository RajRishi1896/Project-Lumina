import 'dart:async';
import 'package:edumesh_android/core/navigation/lumina_transitions.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/lumina_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/services/connectivity_service.dart';
import '../../../core/storage/db_helper.dart';
import '../../../core/services/catalog_service.dart';
import '../../../core/services/flashcard_service.dart';
import '../../../shared/widgets/lumina_settings_sheet.dart';
import '../../../shared/widgets/offline_library_page.dart';
import '../../auth/data/auth_service.dart';
import '../../auth/presentation/profile_picker_page.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';
import 'resource_detail_page.dart';
import 'subject_topics_page.dart';
import 'kiwix_view.dart';
import '../../../core/services/recent_resources.dart';
import 'flashcard_deck_list_page.dart';

/// The main dashboard page displayed after login.
///
/// Shows a search bar, recently-viewed resources, subject category grid, and a
/// local storage usage section. Connection status comes from the
/// [ConnectivityService] heartbeat: no duplicate polling here.
class DashboardPage extends StatefulWidget {
  /// Called when the user taps the search bar: switch to Browse tab.
  final VoidCallback? onBrowseTap;
  const DashboardPage({super.key, this.onBrowseTap});

  /// Creates the state for the [DashboardPage].
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _isConnected = false;

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

  int _flashcardDue = 0;

  String _studentName = '';

  @override
  void initState() {
    super.initState();
    ConnectivityService().addListener(_onConnectivityChanged);
    _onConnectivityChanged();
    _calcTotalStorage();
    _loadSubjects();
    _loadRecentResources();
    unawaited(_loadStudentName());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDashboardStats());
  }

  @override
  void dispose() {
    ConnectivityService().removeListener(_onConnectivityChanged);
    super.dispose();
  }

  void _onConnectivityChanged() {
    if (!mounted) return;
    setState(() {
      _isConnected = ConnectivityService().isOnline;
    });
  }

  /// Loads the active student's name for the profile avatar chip.
  Future<void> _loadStudentName() async {
    final auth = AuthService();
    var name = await auth.getDisplayName();
    if (name == null || name.trim().isEmpty) {
      name = await auth.getLoggedUsername();
    }
    if (!mounted) return;
    setState(() => _studentName = name ?? '');
  }

  /// Loads the flashcard due count from local DB.
  /// Runs once per dashboard load, never in build.
  Future<void> _loadDashboardStats() async {
    try {
      final due = await FlashcardService().dueCount();
      if (!mounted) return;
      setState(() {
        _flashcardDue = due;
      });
    } catch (_) {}
  }

  Future<void> _openFlashcards() async {
    await Navigator.push(
      context,
      luminaRoute(builder: (_) => const FlashcardDeckListPage()),
    );
    if (mounted) unawaited(_loadDashboardStats());
  }

  Future<void> _calcTotalStorage() async {
    // ponytail: paint last measured values instantly, re-measure in background.
    // Recursive dir listing on eMMC takes 0.5-2s and blocks first render.
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedApp = prefs.getInt('cached_app_size_bytes');
      final cachedTotal = prefs.getInt('cached_storage_total_bytes');
      final cachedAvail = prefs.getInt('cached_storage_available_bytes');
      if (cachedApp != null && cachedApp > 0 && cachedTotal != null && cachedTotal > 0 && cachedAvail != null && cachedAvail >= 0) {
        _applyStorageValues(cachedApp, cachedTotal, cachedAvail);
        unawaited(_computeAndCacheStorage());
        return;
      }
    } catch (_) {}
    await _computeAndCacheStorage();
  }

  Future<void> _computeAndCacheStorage() async {
    int apkSize;
    int totalBytes;
    int availableBytes;
    try {
      const channel = MethodChannel('com.edumesh.android/storage');
      final info = await channel.invokeMethod<Map>('getStorageInfo');
      apkSize = info?['apkSize'] as int? ?? 0;
      totalBytes = info?['totalBytes'] as int? ?? 0;
      availableBytes = info?['availableBytes'] as int? ?? 0;
      // ponytail: 0 free bytes is a real state (full disk), not a failure.
      if (apkSize <= 0 || totalBytes <= 0 || availableBytes < 0) {
        throw StateError('incomplete storage info');
      }
    } catch (e) {
      // A transient re-measure failure must not clobber last-known-good
      // values already on screen; N/A only when nothing was painted yet.
      if (_totalStorageUsedStr.isEmpty) {
        _showStorageNA();
      } else {
        debugPrint('Storage re-measure failed, keeping shown values: $e');
      }
      return;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      int appDataSize = 0;
      if (await dir.exists()) {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) appDataSize += await entity.length();
        }
      }
      final appUsedBytes = appDataSize + apkSize;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('cached_app_size_bytes', appUsedBytes);
        await prefs.setInt('cached_storage_total_bytes', totalBytes);
        await prefs.setInt('cached_storage_available_bytes', availableBytes);
      } catch (_) {}
      _applyStorageValues(appUsedBytes, totalBytes, availableBytes);
    } catch (e) {
      // Same clobber guard: keep painted values on a background failure.
      if (_totalStorageUsedStr.isEmpty) {
        _showStorageNA();
      } else {
        debugPrint('Storage re-measure failed, keeping shown values: $e');
      }
    }
  }

  void _showStorageNA() {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _appUsedStr = _otherUsedStr = _freeRemainingStr = l10n.storageUnknown;
      _totalCapacityStr = l10n.storageUnknown;
      _totalStorageUsedStr = l10n.storageUnknown;
    });
  }

  void _applyStorageValues(int appUsedBytes, int totalBytes, int availableBytes) {
      final otherUsedBytes = (totalBytes - availableBytes - appUsedBytes).clamp(0, totalBytes);

      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          final appMb = appUsedBytes / (1024 * 1024);
          _appUsedStr = appMb < 1024 ? '${appMb.toStringAsFixed(1)}${l10n.unitMegabytes}' : '${(appMb / 1024).toStringAsFixed(1)}${l10n.unitGigabytes}';
          final otherGb = otherUsedBytes / (1024 * 1024 * 1024);
          _otherUsedStr = otherGb < 1.0 ? '${(otherUsedBytes / (1024 * 1024)).toStringAsFixed(1)}${l10n.unitMegabytes}' : '${otherGb.toStringAsFixed(1)}${l10n.unitGigabytes}';
          final freeMb = availableBytes / (1024 * 1024);
          _freeRemainingStr = freeMb < 1024 ? '${freeMb.toStringAsFixed(1)}${l10n.unitMegabytes}' : '${(freeMb / 1024).toStringAsFixed(1)}${l10n.unitGigabytes}';
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
      final cached = prefs.getString('cached_subjects');
      if (cached != null && cached.isNotEmpty) {
        final decoded = jsonDecode(cached);
        if (decoded is List) {
          _subjects = decoded.whereType<Map>().map((m) => <String, dynamic>{
            'name': m['name']?.toString() ?? '',
            'symbol': m['symbol']?.toString() ?? '',
          }).toList();
          _subjectsLoading = false;
          if (mounted) setState(() {});
        }
      }

      // Always clear loading immediately — don't block UI on network.
      if (_subjectsLoading) {
        _subjectsLoading = false;
        if (mounted) setState(() {});
      }

      // Fire-and-forget: update from server when reachable.
      unawaited(ApiClient.get('/student/subjects').then((response) async {
        if (mounted && response.statusCode == 200 && response.data is List) {
          final raw = (response.data as List)
              .whereType<Map<String, dynamic>>()
              .toList();
          if (raw.isNotEmpty) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('cached_subjects', jsonEncode(raw));
            if (mounted) setState(() => _subjects = raw);
          }
        }
      }).catchError((_) {}));

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
        // Fresh profiles have no bookmarks/downloads yet: fall back to the
        // local catalog so subjects still show offline on first run.
        if (subjectsSet.isEmpty) {
          try {
            final catalog = await CatalogService().getCatalog();
            for (final c in catalog) {
              if (c.subject.isNotEmpty) subjectsSet.add(c.subject);
            }
          } catch (_) {}
        }
        final local = subjectsSet.map((s) => {'name': s}).toList();
        if (mounted && local.isNotEmpty) {
          setState(() {
            _subjects = local;
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
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
                  // ponytail: builder defers offscreen sections on 1GB devices.
                  child: ListView.builder(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w),
                itemCount: 9,
                itemBuilder: (_, i) => switch (i) {
                  0 => _buildSearchBar(context),
                  1 => _buildFlashcardsEntry(context),
                  2 => SizedBox(height: AppSpacing.xxl.h),
                  3 => _buildRecentlyViewedSection(context),
                  4 => SizedBox(height: AppSpacing.xxl.h),
                  5 => _buildCategories(context),
                  6 => SizedBox(height: AppSpacing.xxl.h),
                  7 => _buildStorageSection(context),
                  _ => SizedBox(height: AppSpacing.xxl.h),
                },
                  ),
                ),
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
            Theme.of(context).brightness == Brightness.dark ? 'assets/images/logo-dark.svg' : 'assets/images/logo-light.svg',
            width: 28.sp,
            height: 28.sp,
          ),
          if (MediaQuery.sizeOf(context).width >= 360) ...[
            SizedBox(width: AppSpacing.md.w),
            Expanded(
              child: Text(l10n.appTitle,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: tt.titleLarge?.copyWith(fontWeight: AppSpacing.weightDisplay, color: cs.primary)),
            ),
          ],
          SizedBox(width: AppSpacing.sm.w),
          _buildServerStatusBadge(),
          SizedBox(width: AppSpacing.sm.w),
          Semantics(
            button: true,
            label: l10n.semanticsProfileSwitcher,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openProfilePicker(context),
              child: SizedBox(
                width: AppSpacing.touchTarget,
                height: AppSpacing.touchTarget,
                child: CircleAvatar(
                  radius: 16.r,
                  backgroundColor: cs.primaryContainer,
                  child: Text(
                    _initials(l10n),
                    style: tt.titleSmall?.copyWith(
                      color: cs.onPrimaryContainer,
                      fontWeight: AppSpacing.weightStrong,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: AppSpacing.sm.w),
          Semantics(
            button: true,
            label: l10n.semanticsSettings,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _showSettings(context),
              child: SizedBox(
                width: AppSpacing.touchTarget,
                height: AppSpacing.touchTarget,
                child: Icon(Icons.settings, color: cs.primary, size: 24.sp),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServerStatusBadge() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    Color bgColor = _isConnected ? cs.secondaryContainer : cs.errorContainer;
    Color textColor = _isConnected ? cs.onSecondaryContainer : cs.onErrorContainer;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm.w, vertical: AppSpacing.xs.h),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(AppSpacing.radiusFull), border: Border.all(color: textColor)),
      child: Text(_isConnected ? l10n.serverStatusConnected : l10n.serverStatusDisconnected,
        maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodySmall?.copyWith(color: textColor)),
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

  /// Compact entry chip into the student's flashcard decks, with a due-today badge.
  Widget _buildFlashcardsEntry(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.only(top: AppSpacing.lg.h),
      child: Semantics(
        button: true,
        label: l10n.flashcardMyDecks,
        child: GestureDetector(
          onTap: _openFlashcards,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w, vertical: AppSpacing.md.h),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm.r),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(
              children: [
                Container(
                  width: 40.w,
                  height: 40.w,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.style_rounded, color: cs.primary, size: 22.sp),
                ),
                SizedBox(width: AppSpacing.md.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.flashcardMyDecks,
                          style: tt.titleSmall?.copyWith(color: cs.onSurface, fontWeight: AppSpacing.weightStrong)),
                      if (_flashcardDue > 0) SizedBox(height: AppSpacing.xs.h),
                      if (_flashcardDue > 0)
                        Text(l10n.flashcardDueToday(_flashcardDue),
                            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (_flashcardDue > 0)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm.w, vertical: AppSpacing.xs.h),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                    ),
                    child: Text('$_flashcardDue',
                        style: tt.labelSmall?.copyWith(color: cs.onPrimary, fontWeight: AppSpacing.weightStrong)),
                  ),
                SizedBox(width: AppSpacing.sm.w),
                Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
              ],
            ),
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
      final resp = await fetchWithLoading(
        context,
        ApiClient.get('/zim/page', queryParameters: {'article_id': id})
            .timeout(const Duration(seconds: 8)),
      );
      final html = resp.data?['html']?.toString();
      if (!mounted || html == null || html.isEmpty) return;
      unawaited(Navigator.push(context, luminaRoute(
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
          height: 120.r,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _recentResources.length,
            separatorBuilder: (_, __) => SizedBox(width: AppSpacing.sm.w),
            itemBuilder: (context, index) {
        final r = _recentResources[index];
        final type = r['type'] ?? '';
        final icon = _iconForResourceType(type);
        // ponytail: one scale (.r) for both axes so the card stays square
        final side = 120.r;
        return GestureDetector(
                onTap: () {
                  if (type == 'kiwix') {
                    _openRecentKiwix(r);
                  } else {
                    Navigator.push(context, luminaRoute(
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
                  width: side,
                  height: side,
                  padding: EdgeInsets.all(AppSpacing.md.w),
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm.r),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 24.sp, color: cs.primary),
                      SizedBox(height: AppSpacing.xs.h),
                      Flexible(
                        child: Text(r['title'] ?? '', style: tt.labelSmall?.copyWith(color: cs.onSurface),
                          maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                      ),
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
          Wrap(
            spacing: AppSpacing.sm.w,
            runSpacing: AppSpacing.sm.h,
            children: _subjects.map((subject) {
              final name = subject['name'] as String? ?? '';
              return SizedBox(
                width: 160.w,
                height: 80.h,
                child: GestureDetector(
                  onTap: () => Navigator.push(context, luminaRoute(
                    builder: (_) => SubjectTopicsPage(subject: name),
                  )),
                  child: Container(
                    padding: EdgeInsets.all(AppSpacing.md.w),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm.r),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40.w,
                          height: 40.w,
                          decoration: BoxDecoration(
                            color: cs.primary.withAlpha(31),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(_iconForSubject(name), color: cs.primary, size: 20.sp),
                        ),
                        SizedBox(width: AppSpacing.sm.w),
                        Expanded(
                          child: Text(name, style: tt.labelMedium?.copyWith(color: cs.onSurface),
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
                ),
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
    return GestureDetector(
      onTap: () => Navigator.push(context,
          luminaRoute(builder: (_) => const OfflineLibraryPage())),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l10n.sectionLocalStorage,
                    style: tt.titleLarge?.copyWith(
                        fontWeight: AppSpacing.weightDisplay,
                        color: cs.onSurface)),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
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
      ),
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
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(top: AppSpacing.sm.h),
      child: Wrap(spacing: AppSpacing.md.w, runSpacing: AppSpacing.xs.h, children: [_buildLegendItem(LuminaColors.academicTeal, l10n.storageLegendAppLabel, _appUsedStr), _buildLegendItem(LuminaColors.saffron, l10n.storageLegendOtherLabel, _otherUsedStr), _buildLegendItem(cs.outlineVariant, l10n.storageLegendFreeLabel, _freeRemainingStr)]),
    );
  }

  Widget _buildLegendItem(Color color, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8.w, height: 8.w, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      SizedBox(width: AppSpacing.xs.w),
      Text(label, style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
      SizedBox(width: AppSpacing.xs.w),
      Text(value, style: tt.labelSmall?.copyWith(fontWeight: AppSpacing.weightStrong, color: cs.onSurface)),
    ]);
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
    showLuminaSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusLg))), builder: (_) => const LuminaSettingsSheet());
  }

  String _initials(AppLocalizations l10n) {
    final name = _studentName.trim();
    if (name.isEmpty) return l10n.initialsFallback;
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return parts[0][0].toUpperCase();
  }

  void _openProfilePicker(BuildContext context) {
    Navigator.of(context).push(
      luminaRoute(builder: (_) => const ProfilePickerPage()),
    );
  }

}

