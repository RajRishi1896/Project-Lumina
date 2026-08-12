import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:path_provider/path_provider.dart';
import 'package:edumesh_android/core/models/course.dart';
import 'package:edumesh_android/core/services/course_service.dart';
import 'package:edumesh_android/core/recommendation/on_device_scorer.dart';
import 'package:edumesh_android/core/constants/app_spacing.dart';
import 'package:edumesh_android/core/constants/lumina_colors.dart';
import 'package:edumesh_android/features/auth/data/auth_service.dart';
import 'package:edumesh_android/shared/services/connectivity_service.dart';
import 'package:edumesh_android/core/storage/db_helper.dart';
import 'course_player_page.dart';
import 'search_page.dart';
import 'kiwix_view.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';
import 'package:edumesh_android/core/network/api_client.dart';
import 'package:edumesh_android/shared/services/zim_sync_service.dart';
import 'package:edumesh_android/core/models/zim_article_model.dart';
import 'package:edumesh_android/core/services/recent_resources.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Unified browse page with three sub-tabs: Courses, Resources, Wiki.
class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key});

  @override
  BrowsePageState createState() => BrowsePageState();
}

class BrowsePageState extends State<BrowsePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  /// Switch to a specific tab. 0=Courses, 1=Resources, 2=Wiki.
  void switchTab(int index) {
    _tabController.animateTo(index);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w),
              child: TabBar(
                controller: _tabController,
                labelColor: cs.primary,
                unselectedLabelColor: cs.onSurfaceVariant,
                indicatorColor: cs.primary,
                indicatorWeight: 3.0,
                tabs: [
                  Tab(text: l10n.browseTabCourses),
                  Tab(text: l10n.browseTabResources),
                  Tab(text: l10n.browseTabWiki),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                   _CoursesTab(),
                   _ResourcesTab(),
                   _WikiTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Courses sub-tab — enrolled, recommended, similar, all courses.
class _CoursesTab extends StatefulWidget {
  const _CoursesTab();
  @override
  State<_CoursesTab> createState() => _CoursesTabState();
}

class _CoursesTabState extends State<_CoursesTab> {
  bool _loading = true;
  List<Course> _recommended = [];
  List<Course> _allCourses = [];
  List<({Course course, Map<String, dynamic>? progress})> _enrolledCourses = [];
  List<Course> _similarCourses = [];
  String? _grade;
  String? _error;
  String _searchQuery = '';
  bool _showAll = false;
  String _filterGrade = '';
  String _filterSubject = '';
  bool get _hasActiveFilters => _filterGrade.isNotEmpty || _filterSubject.isNotEmpty;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadData();
    CourseService().addListener(_onCourseServiceChanged);
  }

  void _onCourseServiceChanged() {
    if (!mounted) return;
    setState(() { _enrolledCourses = CourseService().enrolledCourses; });
  }

  Future<void> _loadData() async {
    _loading = true;
    if (mounted) setState(() {});
    try {
      _grade = await AuthService().getGradeOrDefault();
      if (ConnectivityService().isOnline) await CourseService().fetchCatalog();
      _allCourses = await CourseService().getCachedCatalog();
      await CourseService().loadEnrolledCourses();
      _enrolledCourses = CourseService().enrolledCourses;
      if (_grade != null && _grade!.isNotEmpty) {
        _recommended = await OnDeviceScorer.getRecommendedCourses('', _grade!);
      }
      final db = await DBHelper().database;
      final similarRows = await db.query('similar_courses');
      final similarIds = similarRows.map((r) => (r['similar_course_id'] ?? '').toString()).toSet();
      _similarCourses = _allCourses.where((c) => similarIds.contains(c.id)).toList();
    } catch (e) { _error = e.toString(); }
    _loading = false;
    if (mounted) setState(() {});
  }

  List<Course> get _filteredCourses {
    var courses = _allCourses;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      courses = courses.where((c) =>
        c.title.toLowerCase().contains(q) ||
        c.subject.toLowerCase().contains(q) ||
        c.description?.toLowerCase().contains(q) == true
      ).toList();
    }
    if (_filterGrade.isNotEmpty) {
      courses = courses.where((c) => c.grade.toString() == _filterGrade).toList();
    }
    if (_filterSubject.isNotEmpty) {
      courses = courses.where((c) => c.subject.toLowerCase().contains(_filterSubject.toLowerCase())).toList();
    }
    return courses;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    CourseService().removeListener(_onCourseServiceChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (_loading) return Center(child: CircularProgressIndicator(strokeWidth: 3.w));
    if (_error != null && _allCourses.isEmpty && _enrolledCourses.isEmpty) {
      final isOffline = !ConnectivityService().isOnline;
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(isOffline ? Icons.cloud_off_rounded : Icons.error_outline,
            size: 48.sp, color: isOffline ? cs.onSurfaceVariant : cs.error),
        SizedBox(height: AppSpacing.md.h),
        Text(isOffline ? l10n.browseNotConnected : l10n.browseCouldNotLoad,
            style: tt.bodyLarge?.copyWith(color: cs.onSurface)),
        if (isOffline) ...[
          SizedBox(height: AppSpacing.xs.h),
          Text(l10n.browseNoCoursesOffline,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ] else if (_error != null) ...[
          SizedBox(height: AppSpacing.sm.h),
          Text(_error!, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
        SizedBox(height: AppSpacing.lg.h),
        FilledButton(onPressed: _loadData, child: Text(l10n.errorRetryButton)),
      ]));
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: AppSpacing.md.h),
          _buildSearchBar(cs, tt, l10n),
          if (_hasActiveFilters) ...[
            SizedBox(height: AppSpacing.sm.h),
            Row(children: [
              Icon(Icons.filter_alt_rounded, size: 14.sp, color: cs.primary),
              SizedBox(width: AppSpacing.xs.w),
              Expanded(child: Text(l10n.filtersActiveLabel,
                  style: tt.titleSmall?.copyWith(color: cs.primary))),
              TextButton.icon(
                icon: Icon(Icons.clear_all, size: 16.sp),
                label: Text(l10n.clearFiltersButton),
                onPressed: () => setState(() { _filterGrade = ''; _filterSubject = ''; }),
                style: TextButton.styleFrom(foregroundColor: cs.error, padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
              ),
            ]),
          ],
          SizedBox(height: AppSpacing.md.h),
          if (_enrolledCourses.isNotEmpty) ...[
            _buildSectionHeader(cs, tt, l10n.browseMyCourses),
            SizedBox(height: AppSpacing.sm.h),
            _buildEnrolledList(cs, tt, l10n),
            SizedBox(height: AppSpacing.section.h),
          ],
          if (_recommended.isNotEmpty && !_showAll) ...[
            _buildSectionHeader(cs, tt, l10n.sectionRecommendedForYou),
            SizedBox(height: AppSpacing.sm.h),
            _buildHorizontalList(_recommended, cs, tt, l10n),
            SizedBox(height: AppSpacing.section.h),
          ],
          if (_similarCourses.isNotEmpty && !_showAll) ...[
            _buildSectionHeader(cs, tt, l10n.browseSimilarCourses),
            SizedBox(height: AppSpacing.sm.h),
            _buildHorizontalList(_similarCourses, cs, tt, l10n),
            SizedBox(height: AppSpacing.section.h),
          ],
          _buildSectionHeader(cs, tt, l10n.browseAllCourses,
            trailing: _recommended.isNotEmpty
              ? TextButton(onPressed: () => setState(() => _showAll = !_showAll),
                  child: Text(_showAll ? l10n.browseShowRecommended : l10n.browseShowAll))
              : null,
          ),
          SizedBox(height: AppSpacing.sm.h),
          _buildAllCoursesList(cs, tt, l10n),
          SizedBox(height: AppSpacing.xxl.h),
        ],
      ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(ColorScheme cs, TextTheme tt, String title, {Widget? trailing}) {
    return Row(children: [
      Text(title, style: tt.titleLarge?.copyWith(fontWeight: AppSpacing.weightDisplay, color: cs.onSurface)),
      const Spacer(),
      if (trailing != null) trailing,
    ]);
  }

  Widget _buildSearchBar(ColorScheme cs, TextTheme tt, AppLocalizations l10n) {
    return Row(children: [
      Expanded(
        child: TextField(
          controller: _searchController,
          onChanged: (v) {
            _searchDebounce?.cancel();
            _searchDebounce = Timer(const Duration(milliseconds: 300), () {
              if (mounted) setState(() => _searchQuery = v);
            });
          },
          decoration: InputDecoration(
            hintText: l10n.browseSearchHint,
            prefixIcon: Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
            suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(icon: Icon(Icons.clear, color: cs.onSurfaceVariant),
                  onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); })
              : null,
            filled: true,
            fillColor: cs.surfaceContainerHighest,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusSm.r), borderSide: BorderSide.none),
            contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w, vertical: AppSpacing.md.h),
          ),
        ),
      ),
      SizedBox(width: AppSpacing.sm.w),
      IconButton(
        icon: Icon(
          _hasActiveFilters ? Icons.filter_alt_rounded : Icons.filter_alt_outlined,
          color: _hasActiveFilters ? cs.primary : cs.onSurfaceVariant,
        ),
        onPressed: _showCourseFilterSheet,
      ),
    ]);
  }

  void _showCourseFilterSheet() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    final allGrades = _allCourses.map((c) => c.grade.toString()).where((g) => g.isNotEmpty).toSet().toList()..sort();
    final allSubjects = _allCourses.map((c) => c.subject).where((s) => s.isNotEmpty).toSet().toList()..sort();
    String tempGrade = _filterGrade;
    String tempSubject = _filterSubject;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20.r))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(24.w, 24.h, 24.w, MediaQuery.of(ctx).viewInsets.bottom + 24.h),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.filterSheetTitle, style: tt.titleLarge?.copyWith(color: cs.onSurface)),
                  SizedBox(height: AppSpacing.lg.h),
                  Text(l10n.filterGradeHeader, style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
                  SizedBox(height: AppSpacing.sm.h),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: tempGrade.isEmpty ? '' : (tempGrade == _grade ? '__my_grade__' : tempGrade),
                    items: [
                      DropdownMenuItem(value: '', child: Text(l10n.filterAllGrades)),
                      if (_grade != null && _grade!.isNotEmpty)
                        DropdownMenuItem(value: '__my_grade__', child: Text(l10n.filterMyGrade)),
                      ...allGrades.map((g) => DropdownMenuItem(value: g, child: Text(g))),
                    ],
                    onChanged: (v) => setSheetState(() {
                      if (v == null || v == '') {
                        tempGrade = '';
                      } else if (v == '__my_grade__') {
                        tempGrade = _grade ?? '';
                      } else {
                        tempGrade = v;
                      }
                    }),
                  ),
                  SizedBox(height: AppSpacing.lg.h),
                  Text(l10n.filterSubjectHeader, style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
                  SizedBox(height: AppSpacing.sm.h),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: tempSubject,
                    items: [
                      DropdownMenuItem(value: '', child: Text(l10n.filterSubjectHint)),
                      ...allSubjects.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                    ],
                    onChanged: (v) => setSheetState(() => tempSubject = v ?? ''),
                  ),
                  SizedBox(height: AppSpacing.xxl.h),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setSheetState(() { tempGrade = ''; tempSubject = ''; }),
                        child: Text(l10n.filterResetButton),
                      ),
                    ),
                    SizedBox(width: AppSpacing.md.w),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          setState(() { _filterGrade = tempGrade; _filterSubject = tempSubject; });
                          Navigator.pop(ctx);
                        },
                        child: Text(l10n.filterApplyButton),
                      ),
                    ),
                  ]),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEnrolledList(ColorScheme cs, TextTheme tt, AppLocalizations l10n) {
    return SizedBox(
      height: 200.h,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _enrolledCourses.length,
        separatorBuilder: (_, __) => SizedBox(width: AppSpacing.md.w),
        itemBuilder: (ctx, i) {
          final entry = _enrolledCourses[i];
          final course = entry.course;
          final progress = entry.progress;
          final completedCount = (progress?['completed_count'] as num?)?.toInt() ?? 0;
          final totalResources = (progress?['total_resources'] as num?)?.toInt() ?? 0;
          final pct = totalResources > 0 ? completedCount / totalResources : 0.0;
          return SizedBox(width: 200.w, child: Card(
            child: InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CoursePlayerPage(course: course))),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm.r),
              child: Padding(padding: EdgeInsets.all(AppSpacing.lg.w), child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(height: 72.h, decoration: BoxDecoration(color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm.r)),
                    child: Center(child: Icon(Icons.school, size: 28.sp, color: cs.primary))),
                  SizedBox(height: AppSpacing.sm.h),
                  Text(course.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: tt.titleSmall?.copyWith(color: cs.onSurface)),
                  SizedBox(height: AppSpacing.xs.h),
                  LinearProgressIndicator(value: pct, backgroundColor: cs.surfaceContainerHighest),
                  SizedBox(height: AppSpacing.xs.h),
                  Text(l10n.browseProgressFormat(completedCount, totalResources),
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  const Spacer(),
                  SizedBox(width: double.infinity, child: FilledButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CoursePlayerPage(course: course))),
                    child: Text(l10n.buttonContinue),
                  )),
                ],
              )),
            ),
          ));
        },
      ),
    );
  }

  Widget _buildHorizontalList(List<Course> courses, ColorScheme cs, TextTheme tt, AppLocalizations l10n) {
    return SizedBox(height: 280.h, child: ListView.separated(
      scrollDirection: Axis.horizontal, itemCount: courses.length,
      separatorBuilder: (_, __) => SizedBox(width: AppSpacing.md.w),
      itemBuilder: (ctx, i) => SizedBox(width: 200.w, child: _buildCourseCard(courses[i], cs, tt, l10n)),
    ));
  }

  Widget _buildCourseCard(Course course, ColorScheme cs, TextTheme tt, AppLocalizations l10n) {
    final isEnrolled = _enrolledCourses.any((e) => e.course.id == course.id);
    return Card(child: InkWell(
      onTap: isEnrolled ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => CoursePlayerPage(course: course))) : null,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm.r),
      child: Padding(padding: EdgeInsets.all(AppSpacing.lg.w), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(height: 80.h, decoration: BoxDecoration(color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm.r)),
            child: Center(child: Icon(Icons.school, size: 32.sp, color: cs.primary))),
          SizedBox(height: AppSpacing.sm.h),
          Text(course.title, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: tt.titleSmall?.copyWith(color: cs.onSurface)),
          SizedBox(height: AppSpacing.xs.h),
          Row(children: [
            Chip(label: Text(course.subject, style: tt.labelSmall),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
            SizedBox(width: AppSpacing.xs.w),
            Chip(label: Text(l10n.browseClassLabel(course.grade), style: tt.labelSmall),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
          ]),
          const Spacer(),
          if (isEnrolled)
            SizedBox(width: double.infinity, child: OutlinedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CoursePlayerPage(course: course))),
              child: Text(l10n.buttonContinue)))
          else
            SizedBox(width: double.infinity, child: FilledButton(
              onPressed: () async { await CourseService().enroll(course.id); if (mounted) await _loadData(); },
              child: Text(l10n.browseEnroll))),
        ],
      )),
    ));
  }

  Widget _buildAllCoursesList(ColorScheme cs, TextTheme tt, AppLocalizations l10n) {
    final courses = _filteredCourses;
    if (courses.isEmpty) {
      return Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.section.h),
      child: Center(child: Column(children: [
        Icon(Icons.search_off, size: 40.sp, color: cs.onSurfaceVariant),
        SizedBox(height: AppSpacing.md.h),
        Text(_searchQuery.isNotEmpty ? l10n.browseNoMatchingCourses : l10n.browseNoCoursesAvailable,
          style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
      ])),
      );
    }
    return ListView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      itemCount: courses.length,
      itemBuilder: (ctx, i) => Padding(
        padding: EdgeInsets.only(bottom: AppSpacing.md.h),
        child: _buildCourseCard(courses[i], cs, tt, l10n)),
    );
  }
}

/// Resources sub-tab — catalog resources with search, filters, download, bookmark.
class _ResourcesTab extends StatefulWidget {
  const _ResourcesTab();
  @override
  State<_ResourcesTab> createState() => _ResourcesTabState();
}

class _ResourcesTabState extends State<_ResourcesTab> {
  @override
  Widget build(BuildContext context) {
    return const SearchPage(embedded: true);
  }
}

/// Wiki sub-tab — server-side ZIM search/browse with infinite scroll.
class _WikiTab extends StatefulWidget {
  const _WikiTab();
  @override
  State<_WikiTab> createState() => _WikiTabState();
}

class _WikiTabState extends State<_WikiTab> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  List<ZimArticle> _articles = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String _query = '';
  bool _hasMore = false;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    ZimSyncService.instance.loadDownloadedIds();
    _fetchFirstPage();
  }

  bool get isOffline => !ConnectivityService().isOnline;

  Future<void> _fetchFirstPage() async {
    _loading = true;
    if (mounted) setState(() {});
    _requestId++;
    final myId = _requestId;
    try {
      final result = _query.isEmpty
          ? await ZimSyncService.instance.browseOnServer(offset: 0, limit: 50)
          : await ZimSyncService.instance.searchOnServer(_query, offset: 0, limit: 50);
      if (myId != _requestId) return;
      _articles = result.articles;
      _hasMore = result.hasMore;
      _error = null;
    } catch (e) {
      if (myId != _requestId) return;
      _articles = [];
      _hasMore = false;
      _error = e.toString();
    }
    _loading = false;
    if (mounted) setState(() {});
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _query = value.trim().replaceAll(RegExp(r'\s+'), ' ');
      _articles = [];
      _hasMore = false;
      _fetchFirstPage();
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _query = '';
    _articles = [];
    _hasMore = false;
    _fetchFirstPage();
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || isOffline) return;
    _loadingMore = true;
    if (mounted) setState(() {});
    _requestId++;
    final myId = _requestId;
    try {
      final result = _query.isEmpty
          ? await ZimSyncService.instance.browseOnServer(offset: _articles.length, limit: 50)
          : await ZimSyncService.instance.searchOnServer(_query, offset: _articles.length, limit: 50);
      if (myId != _requestId) return;
      _articles = [..._articles, ...result.articles];
      _hasMore = result.hasMore;
    } catch (_) {}
    _loadingMore = false;
    if (mounted) setState(() {});
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollEndNotification &&
        notification.metrics.pixels >= notification.metrics.maxScrollExtent - 200) {
      _loadMore();
    }
    return false;
  }

  Future<void> _openArticle(ZimArticle article) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    try {
      String? html;
      try {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/zim_${article.articleId.replaceAll('/', '_')}.html');
        if (await file.exists()) html = await file.readAsString();
      } catch (_) {}
      if (html == null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          html = prefs.getString('zim_page_${article.articleId}');
        } catch (_) {}
      }
      if (html == null) {
        final resp = await ApiClient.get('/zim/page', queryParameters: {'article_id': article.articleId})
            .timeout(const Duration(seconds: 8));
        html = resp.data?['html']?.toString() ?? '';
        if (html.isNotEmpty) {
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('zim_page_${article.articleId}', html);
          } catch (_) {}
        }
      }
      if (!mounted) return;
      if (html.isNotEmpty) {
        unawaited(RecentResources.record(article.articleId, article.title, 'kiwix'));
        unawaited(Navigator.push(context, MaterialPageRoute(builder: (_) => KiwixView(initialHtml: html, title: article.title, baseUrl: ApiClient.baseUrl))));
      } else {
        messenger.showSnackBar(SnackBar(content: Text(l10n.zimArticleNotFound)));
      }
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(l10n.errorNoServerNoCache)));
    }
  }

  Future<void> _downloadArticle(ZimArticle article) async {
    try {
      final res = await ApiClient.get('/zim/page', queryParameters: {'article_id': article.articleId})
          .timeout(const Duration(seconds: 10));
      var html = res.data['html'] as String? ?? '';
      if (html.isEmpty) return;
      final assetPattern = RegExp(r"""(/zim/asset\?archive_id=[^"'&]+&path=([^"'&]+))""");
      final matches = assetPattern.allMatches(html).toList();
      const concurrency = 5;
      for (var i = 0; i < matches.length; i += concurrency) {
        final batch = matches.sublist(i, (i + concurrency).clamp(0, matches.length));
        await Future.wait(batch.map((m) async {
          final fullUrl = m.group(1)!;
          final assetPath = Uri.decodeComponent(m.group(2)!);
          try {
            final assetResp = await ApiClient.get('/zim/asset', queryParameters: {
              'archive_id': article.archiveId, 'path': assetPath,
            }).timeout(const Duration(seconds: 5));
            if (assetResp.data is List<int>) {
              final b64 = base64Encode(assetResp.data as List<int>);
              final ext = assetPath.split('.').last.toLowerCase();
              const mimeMap = {'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
                'gif': 'image/gif', 'svg': 'image/svg+xml', 'css': 'text/css', 'js': 'application/javascript'};
              final mime = mimeMap[ext] ?? 'application/octet-stream';
              html = html.replaceAll(fullUrl, 'data:$mime;base64,$b64');
            }
          } catch (_) {}
        }));
      }
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/zim_${article.articleId}.html');
      await file.writeAsString(html);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('zim_page_${article.articleId}', html);
      } catch (_) {}
      await ZimSyncService.instance.markDownloaded(article.articleId);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.snackbarDownloadFailed),
          action: SnackBarAction(label: l10n.buttonRetry, onPressed: () => _downloadArticle(article)),
        ));
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;

    if (_loading) return Center(child: CircularProgressIndicator(strokeWidth: 3.w));
    if (_error != null && _articles.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(isOffline ? Icons.cloud_off_rounded : Icons.error_outline,
            size: 48.sp, color: isOffline ? cs.onSurfaceVariant : cs.error),
        SizedBox(height: AppSpacing.md.h),
        Text(isOffline ? l10n.browseNotConnected : _error!,
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        if (isOffline) ...[
          SizedBox(height: AppSpacing.xs.h),
          Text(l10n.zimNoArticlesOffline,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
        SizedBox(height: AppSpacing.lg.h),
        FilledButton(onPressed: _fetchFirstPage, child: Text(l10n.errorRetryButton)),
      ]));
    }

    final itemCount = _articles.length + (_hasMore ? 1 : 0);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(AppSpacing.lg.w, AppSpacing.md.h, AppSpacing.lg.w, 0),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: l10n.zimSearchHint,
                  prefixIcon: Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
                  suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(icon: Icon(Icons.clear, color: cs.onSurfaceVariant),
                        onPressed: _clearSearch)
                    : null,
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusSm.r), borderSide: BorderSide.none),
                  contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w, vertical: AppSpacing.md.h),
                ),
              ),
            ),
            Expanded(
              child: _articles.isEmpty
                ? Center(child: Text(
                    _query.isEmpty
                        ? (isOffline ? l10n.browseNotConnected : l10n.zimNoArticlesEmpty)
                        : l10n.zimNoResultsEmpty,
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)))
                : NotificationListener<ScrollNotification>(
                    onNotification: _onScrollNotification,
                    child: ListView.builder(
                      padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w, vertical: AppSpacing.sm.h),
                      itemCount: itemCount,
                      itemBuilder: (ctx, i) {
                        if (i >= _articles.length) {
                          return Padding(
                            padding: EdgeInsets.symmetric(vertical: AppSpacing.md.h),
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2.w)),
                          );
                        }
                        final article = _articles[i];
                        final isDownloaded = ZimSyncService.instance.downloadedIds.contains(article.articleId);
                        final offlineUnavailable = isOffline && !isDownloaded;
                        return Opacity(
                          opacity: offlineUnavailable ? 0.45 : 1.0,
                          child: Card(
                            color: offlineUnavailable ? cs.surfaceContainerHighest : null,
                            child: ListTile(
                              leading: article.hasThumbnail
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(6.r),
                                    child: Image.network(
                                      '${ApiClient.baseUrl}/zim/thumbnail?article_id=${article.articleId}',
                                      width: 48, height: 48, fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => CircleAvatar(
                                        backgroundColor: cs.primaryContainer,
                                        child: Icon(Icons.article, color: cs.primary)),
                                    ))
                                : CircleAvatar(backgroundColor: cs.primaryContainer,
                                    child: Icon(Icons.article, color: cs.primary)),
                              title: Row(children: [
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                                  decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(4.r)),
                                  child: Text(l10n.badgeKiwixWiki, style: tt.labelSmall?.copyWith(
                                    color: cs.onPrimary, fontWeight: AppSpacing.weightStrong, letterSpacing: 1)),
                                ),
                                SizedBox(width: AppSpacing.sm.w),
                                Expanded(child: Text(article.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                                  style: tt.bodyLarge?.copyWith(color: cs.onSurface))),
                              ]),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                IconButton(
                                  icon: Icon(isDownloaded ? Icons.check_circle : Icons.download_outlined,
                                    color: isDownloaded ? LuminaColors.successGreen : cs.primary),
                                  onPressed: isDownloaded ? null : () => _downloadArticle(article)),
                                Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                              ]),
                              onTap: () => _openArticle(article),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
