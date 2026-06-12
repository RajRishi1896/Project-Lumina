import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:edumesh_android/shared/services/save_resource_service.dart';
import 'package:edumesh_android/shared/services/download_service.dart';
import 'package:edumesh_android/core/models/resource_model.dart';
import 'package:edumesh_android/core/constants/lumina_colors.dart';
import 'package:edumesh_android/core/constants/app_spacing.dart';
import 'package:edumesh_android/core/network/api_client.dart';
import '../../../core/services/activity_tracker.dart';
import '../../../shared/services/download_queue.dart';
import '../../../shared/services/connectivity_service.dart';
import '../../../shared/services/zim_api_service.dart';
import '../../../shared/services/zim_cache_service.dart';
import '../../../shared/widgets/resource_thumbnail.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';
import 'resource_detail_page.dart';
import 'kiwix_view.dart';

/// A page for browsing, searching, and filtering all available resources.
///
/// Displays a search field with type/grade/subject filters, a recommended-for-you
/// section, and a scrollable list of matching resources. Supports download,
/// bookmarking, and offline queueing.
class SearchPage extends StatefulWidget {
  /// The student's grade, used to pre-select the grade filter and compute
  /// recommendations.
  final String initialGrade;

  /// Whether to open the filter sheet immediately on page load.
  final bool openFilters;

  const SearchPage({super.key, this.initialGrade = '', this.openFilters = false});

  /// Creates the state for the [SearchPage].
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<Map<String, dynamic>> _searchIndex = [];
  List<ResourceModel> _allResources = [];
  Map<dynamic, bool> _savedStatuses = {};
  Set<String> _downloadedIds = {};
  Set<String> _pendingIds = {};
  final Set<String> _downloadingIds = {};
  List<Map<String, dynamic>> _zimArticles = [];
  List<Map<String, dynamic>> _filteredResults = [];
  bool _isLoading = true;
  String? _loadError;

  // Filter state
  Set<ResourceType> _selectedTypes = {};
  Set<String> _selectedGrades = {};
  String _subjectFilter = '';
  String _sortBy = 'title_asc';
  bool get _hasActiveFilters =>
      _selectedTypes.isNotEmpty || _selectedGrades.isNotEmpty || _subjectFilter.isNotEmpty || _sortBy != 'title_asc';

  @override
  void initState() {
    super.initState();
    _loadResources();
    _refreshSavedResources();
    _loadDownloadStatus();
    if (widget.initialGrade.isNotEmpty) {
      _selectedGrades = {widget.initialGrade};
    }
    if (widget.openFilters) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showFilterSheet());
    }
    _applyFilters();
  }

  Future<void> _loadResources() async {
    if (mounted) setState(() { _isLoading = true; _loadError = null; });
    try {
      final resp = await ApiClient.get('/api/catalog').timeout(const Duration(seconds: 8));
      final data = resp.data;
      List<ResourceModel> resources = [];
      if (data is List) {
        resources = data.map((j) => ResourceModel.fromJson(j is Map ? Map<String, dynamic>.from(j) : {})).toList();
      } else if (data is Map && data['items'] is List) {
        resources = (data['items'] as List).map((j) => ResourceModel.fromJson(j is Map ? Map<String, dynamic>.from(j) : {})).toList();
      }
    _allResources = resources;

    _zimArticles = [];
    try {
      final zimResp = await ApiClient.get('/zim/articles', queryParameters: {
        'offset': '0', 'limit': '500',
      }).timeout(const Duration(seconds: 8));
      if (zimResp.data is List) {
        _zimArticles = (zimResp.data as List).cast<Map<String, dynamic>>();
      }
    } catch (_) { } _buildSearchIndex(resources);
    _applyFilters();
  } catch (_) {
      try {
        final local = await SaveResourceService.getAllSavedResourceModels();
        if (local.isNotEmpty) {
        _allResources = local;
        _zimArticles = [];
        _buildSearchIndex(local);
        _applyFilters();
        if (mounted) setState(() { _isLoading = false; _loadError = null; });
          return;
        }
      } catch (_) { } if (mounted) { final l10n = AppLocalizations.of(context)!; setState(() => _loadError = l10n.errorNoServerNoCache); }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _buildSearchIndex(List<ResourceModel> resources) {
    _searchIndex = [];
    for (final r in resources) {
      if (r.type == ResourceType.kiwix) continue;
      _searchIndex.add({
        'title': r.title,
        'searchKeywords': '${r.title} ${r.subject} ${r.grade} ${r.type.toString().split('.').last}'.toLowerCase(),
        'originalObject': r,
        'isZim': false,
      });
    }
    final l10n = AppLocalizations.of(context)!;
    for (final article in _zimArticles) {
      final title = article['title']?.toString() ?? l10n.zimUntitledArticleFallback;
      final id = article['article_id']?.toString() ?? '';
      if (id.isEmpty) continue;
      _searchIndex.add({
        'title': title,
        'searchKeywords': title.toLowerCase(),
        'originalObject': null,
        'isZim': true,
        'articleId': id,
      });
    }
  }

  Future<void> _loadDownloadStatus() async {
    try {
      final ids = await DownloadService().getAllDownloadedIds();
      final pIds = await DownloadService().getAllPendingIds();
      if (mounted) {
        setState(() {
          _downloadedIds = ids;
          _pendingIds = pIds;
        });
      }
    } catch (_) { } }

  Future<void> _refreshSavedResources() async {
    final results = await SaveResourceService.getAllSavedResourceModels();
    if (mounted) {
      final savedIds = results.map((r) => r.id).toSet();
      final statusMap = <dynamic, bool>{};
      for (final item in _searchIndex) {
        if (item['isZim'] == true) continue;
        final original = item['originalObject'];
        statusMap[original.id] = savedIds.contains(original.id.toString());
      }
      setState(() => _savedStatuses = statusMap);
    }
  }

  Future<void> _openZimArticle(String articleId, String title) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    try {
      String? html = await ZimCacheService.getPage(articleId);
      if (html == null) {
        final pageData = await ZimApiService().fetchPage(articleId);
        html = pageData['html']?.toString() ?? '';
        if (html.isNotEmpty) {
          await ZimCacheService.savePage(articleId, html);
        }
      }
      if (!mounted) return;
      if (html.isNotEmpty) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => KiwixView(initialHtml: html, title: title),
        ));
      } else {
        messenger.showSnackBar(SnackBar(content: Text(l10n.zimArticleNotFound)));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.zimFailedToLoadArticle(e.toString()))));
      }
    }
  }

  Widget _buildDownloadButton(dynamic original, ColorScheme cs) {
    final resourceId = original.id.toString();
    final isDownloaded = _downloadedIds.contains(resourceId);
    final isDownloading = _downloadingIds.contains(resourceId);
    final isPending = _pendingIds.contains(resourceId);

    if (isDownloading) {
      return SizedBox(
        width: 24.w,
        height: 24.h,
        child: const CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final icon = isDownloaded
        ? Icons.check_circle
        : isPending
            ? Icons.hourglass_bottom
            : Icons.download_outlined;
    final color = isDownloaded
        ? LuminaColors.successGreen
        : isPending
            ? cs.onSurfaceVariant
            : cs.primary;

    return IconButton(
      icon: Icon(icon, color: color),
      onPressed: isPending
          ? null
          : () async {
        final messenger = ScaffoldMessenger.of(context);
        final l10n = AppLocalizations.of(context)!;
        if (isDownloaded) {
          await DownloadService().deleteDownload(resourceId);
          if (mounted) {
            setState(() => _downloadedIds.remove(resourceId));
          }
          messenger.showSnackBar(SnackBar(
            content: Text(l10n.snackbarDownloadRemoved),
            duration: const Duration(milliseconds: 600),
          ));
        } else {
          final base = ApiClient.dio.options.baseUrl.replaceAll(RegExp(r'/api/?$'), '');
          final url = original.pdfUrl ?? '$base/files/$resourceId';
          final ext = url.contains('.') ? '.${url.split('.').last.split('?').first}' : '.pdf';
          final fileName = '${original.title}$ext';
          final isOnline = ConnectivityService().isOnline;
          if (!isOnline) {
            await DownloadQueue().enqueue(resourceId, url, fileName,
              title: original.title, subject: original.subject,
              grade: original.grade, type: original.type.name,
            );
            if (mounted) {
              setState(() => _pendingIds.add(resourceId));
              messenger.showSnackBar(SnackBar(
                content: Text(l10n.snackbarAddedToQueueOffline),
                duration: const Duration(seconds: 3),
              ));
            }
            return;
          }
          setState(() => _downloadingIds.add(resourceId));
          try {
            final path = await DownloadService().downloadAndTrack(
              resourceId, url, fileName,
              title: original.title,
              subject: original.subject,
              grade: original.grade,
              type: original.type.name,
            );
            if (mounted) {
              setState(() {
                _downloadingIds.remove(resourceId);
                if (path != null) _downloadedIds.add(resourceId);
              });
            }
            if (path != null) {
              messenger.showSnackBar(SnackBar(
                content: Text(l10n.snackbarDownloadComplete),
                duration: const Duration(milliseconds: 600),
              ));
            }
          } catch (e) {
            debugPrint('Download error: $e');
            if (mounted) {
              setState(() => _downloadingIds.remove(resourceId));
            }
            messenger.showSnackBar(SnackBar(
              content: Text(l10n.snackbarDownloadFailed),
              duration: const Duration(milliseconds: 600),
            ));
          }
        }
      },
    );
  }



  Set<String> _getAllGrades() {
    return _searchIndex
        .where((item) => item['isZim'] != true)
        .map((item) => (item['originalObject'].grade ?? '').toString())
        .where((g) => g.isNotEmpty)
        .toSet();
  }

  void _resetFilters() {
    setState(() {
      _selectedTypes.clear();
      _selectedGrades = widget.initialGrade.isNotEmpty ? {widget.initialGrade} : {};
      _subjectFilter = '';
      _sortBy = 'title_asc';
    });
    _applyFilters();
  }

  void _showFilterSheet() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    final allGrades = _getAllGrades().toList()..sort();

    Set<ResourceType> tempTypes = Set.from(_selectedTypes);
    Set<String> tempGrades = Set.from(_selectedGrades);
    String tempSubject = _subjectFilter;
    String tempSort = _sortBy;

    final subjectController = TextEditingController(text: tempSubject);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                24.w, 24.h, 24.w,
                MediaQuery.of(ctx).viewInsets.bottom + 24.h,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.filterSheetTitle,
                      style: tt.titleLarge?.copyWith(
                          color: cs.onSurface)),
                  SizedBox(height: AppSpacing.lg.h),
                  Text(l10n.filterResourceTypeHeader,
                      style: tt.titleSmall?.copyWith(
                          color: cs.onSurfaceVariant)),
                  SizedBox(height: AppSpacing.sm.h),
                  Wrap(
                    spacing: 8.w,
                    runSpacing: 4.h,
                    children: ResourceType.values.map((type) {
                      final label = type.toString().split('.').last;
                      final selected = tempTypes.contains(type);
                      return FilterChip(
                        label: Text(
                            label[0].toUpperCase() + label.substring(1)),
                        selected: selected,
                        onSelected: (val) {
                          setSheetState(() {
                            if (val) {
                              tempTypes.add(type);
                            } else {
                              tempTypes.remove(type);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  SizedBox(height: AppSpacing.lg.h),
                  Row(
                    children: [
                      Text(l10n.filterShowLabel, style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
                      SizedBox(width: AppSpacing.md.w),
                      ChoiceChip(
                        label: Text(l10n.filterMyGrade),
                        selected: tempGrades.contains(widget.initialGrade),
                        onSelected: (_) {
                          setSheetState(() {
                            tempGrades.clear();
                            if (widget.initialGrade.isNotEmpty) tempGrades.add(widget.initialGrade);
                          });
                        },
                      ),
                      SizedBox(width: AppSpacing.sm.w),
                      ChoiceChip(
                        label: Text(l10n.filterAllGrades),
                        selected: tempGrades.isEmpty,
                        onSelected: (_) {
                          setSheetState(() => tempGrades.clear());
                        },
                      ),
                    ],
                  ),
                  SizedBox(height: AppSpacing.lg.h),
                  Text(l10n.filterGradeHeader,
                      style: tt.titleSmall?.copyWith(
                          color: cs.onSurfaceVariant)),
                  SizedBox(height: AppSpacing.sm.h),
                  Wrap(
                    spacing: 8.w,
                    runSpacing: 4.h,
                    children: allGrades.map((grade) {
                      final selected = tempGrades.contains(grade);
                      return FilterChip(
                        label: Text(grade),
                        selected: selected,
                        onSelected: (val) {
                          setSheetState(() {
                            if (val) {
                              tempGrades.add(grade);
                            } else {
                              tempGrades.remove(grade);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  SizedBox(height: AppSpacing.lg.h),
                  Text(l10n.filterSubjectHeader,
                      style: tt.titleSmall?.copyWith(
                          color: cs.onSurfaceVariant)),
                  SizedBox(height: AppSpacing.sm.h),
                  TextField(
                    decoration: InputDecoration(
                      hintText: l10n.filterSubjectHint,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.r)),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12.w, vertical: 10.h),
                    ),
                    controller: subjectController,
                    onChanged: (v) => tempSubject = v,
                  ),
                  SizedBox(height: AppSpacing.lg.h),
                  Text(l10n.filterSortByHeader,
                      style: tt.titleSmall?.copyWith(
                          color: cs.onSurfaceVariant)),
                  SizedBox(height: AppSpacing.sm.h),
                  Wrap(
                    spacing: 8.w,
                    runSpacing: 4.h,
                    children: [
                      _sortChip(l10n.sortTitleAsc, 'title_asc', tempSort,
                          (v) => setSheetState(() => tempSort = v)),
                      _sortChip(l10n.sortTitleDesc, 'title_desc', tempSort,
                          (v) => setSheetState(() => tempSort = v)),
                      _sortChip(l10n.sortByType, 'type', tempSort,
                          (v) => setSheetState(() => tempSort = v)),
                      _sortChip(l10n.sortByGrade, 'grade', tempSort,
                          (v) => setSheetState(() => tempSort = v)),
                    ],
                  ),
                  SizedBox(height: AppSpacing.xxl.h),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setSheetState(() {
                              tempTypes.clear();
                              tempGrades.clear();
                              tempSubject = '';
                              tempSort = 'title_asc';
                            });
                            subjectController.clear();
                          },
                          child: Text(l10n.filterResetButton),
                        ),
                      ),
                      SizedBox(width: AppSpacing.md.w),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                              setState(() {
                                _selectedTypes = tempTypes;
                                _selectedGrades = tempGrades;
                                _subjectFilter = tempSubject;
                                _sortBy = tempSort;
                              });
                              _applyFilters();
                              Navigator.pop(ctx);
                          },
                          child: Text(l10n.filterApplyButton),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() => subjectController.dispose());
  }

  String _sortLabel(String sortBy) {
    final l10n = AppLocalizations.of(context)!;
    switch (sortBy) {
      case 'title_asc': return l10n.sortTitleAsc;
      case 'title_desc': return l10n.sortTitleDesc;
      case 'type': return l10n.sortByType;
      case 'grade': return l10n.sortByGrade;
      default: return sortBy.replaceAll('_', ' ');
    }
  }

  Widget _sortChip(String label, String value, String current,
      void Function(String) onSelected) {
    final tt = Theme.of(context).textTheme;
    final selected = current == value;
    return ChoiceChip(
      label: Text(label, style: tt.labelSmall),
      selected: selected,
      onSelected: (_) => onSelected(value),
      visualDensity: VisualDensity.compact,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilters() {
    final textFiltered = _searchQuery.trim().isEmpty
        ? List<Map<String, dynamic>>.from(_searchIndex)
        : _searchIndex.where((item) {
            return (item['searchKeywords'] as String)
                .contains(_searchQuery.toLowerCase());
          }).toList();

    final List<Map<String, dynamic>> results = textFiltered.where((item) {
      if (item['isZim'] == true) return true;
      final original = item['originalObject'];
      if (_selectedTypes.isNotEmpty && !_selectedTypes.contains(original.type)) return false;
      if (_selectedGrades.isNotEmpty && !_selectedGrades.contains(original.grade)) return false;
      if (_subjectFilter.isNotEmpty && !(original.subject ?? '').toLowerCase().contains(_subjectFilter.toLowerCase())) return false;
      return true;
    }).toList();

    results.sort((a, b) {
      if (a['isZim'] == true && b['isZim'] == true) {
        final at = a['title'] as String? ?? '';
        final bt = b['title'] as String? ?? '';
        return at.compareTo(bt);
      }
      if (a['isZim'] == true) return 1;
      if (b['isZim'] == true) return -1;
      final oa = a['originalObject'];
      final ob = b['originalObject'];
      switch (_sortBy) {
        case 'title_desc':
          return (ob.title ?? '').compareTo(oa.title ?? '');
        case 'type':
          return (oa.type?.index ?? 0).compareTo(ob.type?.index ?? 0);
        case 'grade':
          return (oa.grade ?? '').compareTo(ob.grade ?? '');
        default:
          return (oa.title ?? '').compareTo(ob.title ?? '');
      }
    });

    setState(() => _filteredResults = results);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: cs.surface,
        iconTheme: IconThemeData(color: cs.primary),
        title: Text(l10n.pageTitleBrowseResources,
            style: tt.titleLarge?.copyWith(
                fontWeight: AppSpacing.weightDisplay, color: cs.primary)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _isLoading ? null : _loadResources,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.section.w),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off_rounded,
                            size: 48.sp, color: cs.error),
                        SizedBox(height: AppSpacing.lg.h),
                        Text(_loadError!,
                            textAlign: TextAlign.center,
                            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                        SizedBox(height: AppSpacing.lg.h),
                        FilledButton.tonalIcon(
                          onPressed: _loadResources,
                          icon: const Icon(Icons.refresh),
                          label: Text(l10n.errorRetryButton),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadResources,
                  child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm.h)),
            SliverToBoxAdapter(
              child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w),
                    decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16.r),
                        border: Border.all(color: cs.outlineVariant)),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) {
        ActivityTracker()
            .logAction('search', metadata: value)
            .catchError((_) {});
        setState(() => _searchQuery = value);
        _applyFilters();
      },
                      style: tt.bodyLarge?.copyWith(color: cs.onSurface),
                      decoration: InputDecoration(
                        icon: Icon(Icons.search_rounded,
                            color: cs.onSurfaceVariant),
                        hintText: l10n.searchFieldHint,
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: AppSpacing.sm.w),
                IconButton(
                  icon: Icon(
                    _hasActiveFilters
                        ? Icons.filter_alt_rounded
                        : Icons.filter_alt_outlined,
                    color: _hasActiveFilters
                        ? cs.primary
                        : cs.onSurfaceVariant,
                  ),
                  onPressed: _showFilterSheet,
                ),
              ],
            ),
            ),
            SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md.h)),
            if (_hasActiveFilters)
              SliverToBoxAdapter(
                child: Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.sm.h),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _sortBy != 'title_asc'
                            ? l10n.filtersActiveSorted(_sortLabel(_sortBy))
                            : l10n.filtersActiveLabel,
                        style: tt.titleSmall?.copyWith(
                            color: cs.primary),
                      ),
                    ),
                    TextButton.icon(
                      icon: Icon(Icons.clear_all, size: 16.sp),
                      label: Text(l10n.clearFiltersButton),
                      onPressed: _resetFilters,
                      style: TextButton.styleFrom(
                        foregroundColor: cs.error,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ),
              ),
            if (_searchQuery.trim().isEmpty && !_hasActiveFilters && _filteredResults.isNotEmpty)
              SliverToBoxAdapter(
                child: _buildRecommendedSection(cs),
              ),
            if (_searchQuery.trim().isEmpty && !_hasActiveFilters && _filteredResults.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: AppSpacing.lg.h, bottom: AppSpacing.sm.h),
                  child: Text(l10n.sectionAllResources,
                      style: tt.titleMedium?.copyWith(
                          color: cs.onSurface)),
                ),
              ),
            _filteredResults.isEmpty
                ? SliverFillRemaining(
                    child: Center(
                    child: Text(
                    _searchQuery.trim().isEmpty && !_hasActiveFilters
                        ? l10n.emptyNoResources
                        : l10n.emptyNoSearchResults,
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  )))
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = _filteredResults[index];
                        final isZim = item['isZim'] == true;
                        final dynamic original = item['originalObject'];

                        final isOfflineUnavailable = !isZim && !ConnectivityService().isOnline && !_downloadedIds.contains(original.id.toString());

                        return Opacity(
                          opacity: isOfflineUnavailable ? 0.45 : 1.0,
                          child: ListTile(
                          leading: isZim
                              ? CircleAvatar(
                                  backgroundColor: cs.primaryContainer,
                                  child: Icon(Icons.article, color: cs.primary),
                                )
                              : ResourceThumbnail(resource: original, size: 48),
                          onTap: () {
                            if (isZim) {
                              _openZimArticle(item['articleId'] as String, item['title'] as String);
                              return;
                            }
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ResourceDetailPage(
                                  title: item['title'] as String? ?? '',
                                  subject:
                                      (original.subject ?? '').toString(),
                                  grade: (original.grade ?? '').toString(),
                                  resourceType: original.type.name,
                                  isInitiallySaved:
                                      _savedStatuses[original.id] ?? false,
                                ),
                              ),
                            );
                          },
                          title: Row(
                            children: [
                              if (isZim)
                                Padding(
                                  padding: EdgeInsets.only(right: AppSpacing.sm.w),
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 6.w, vertical: 2.h),
                                    decoration: BoxDecoration(
                                      color: cs.primary,
                                      borderRadius:
                                          BorderRadius.circular(4.r),
                                    ),
                                    child: Text(
                                      l10n.badgeKiwixWiki,
                                      style: tt.labelSmall?.copyWith(
                                        color: cs.onPrimary,
                                        fontWeight: AppSpacing.weightStrong,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: Text(item['title'],
                                    style:
                                        tt.bodyLarge?.copyWith(color: cs.onSurface)),
                              ),
                            ],
                          ),
                          trailing: isZim
                              ? Icon(Icons.chevron_right, color: cs.onSurfaceVariant)
                              : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    _savedStatuses[original.id] ?? false
                                        ? Icons.bookmark
                                        : Icons.bookmark_border,
                                    color: cs.primary,
                                  ),
                                  onPressed: () async {
                                    final messenger =
                                        ScaffoldMessenger.of(context);
                                    final wasSaved =
                                        _savedStatuses[original.id] ?? false;
                                    await SaveResourceService.toggleSaveStatus(
                                        original.id);
                                    if (mounted) {
                                      setState(() => _savedStatuses[original.id] =
                                          !wasSaved);
                                    }
                                    messenger.hideCurrentSnackBar();
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(wasSaved
                                            ? l10n.snackbarRemovedFromSaved
                                            : l10n.snackbarAddedToSaved),
                                        duration:
                                            const Duration(milliseconds: 600),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                _buildDownloadButton(original, cs),
                              ],
                            ),
                        ),
                        );
                      },
                      childCount: _filteredResults.length,
                    ),
                  ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildRecommendedSection(ColorScheme cs) {
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    final recommended = _computeRecommendations();
    if (recommended.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome_rounded, size: 18.sp, color: cs.primary),
            SizedBox(width: AppSpacing.sm.w),
            Text(l10n.sectionRecommendedForYou,
                style: tt.titleMedium?.copyWith(
                    color: cs.onSurface)),
          ],
        ),
        SizedBox(height: AppSpacing.sm.h),
        SizedBox(
          height: 120.h,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: recommended.length,
            separatorBuilder: (_, __) => SizedBox(width: AppSpacing.md.w),
            itemBuilder: (context, index) {
              final r = recommended[index];
              return _buildRecommendationCard(r, cs);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRecommendationCard(ResourceModel r, ColorScheme cs) {
    final tt = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResourceDetailPage(
            title: r.title,
            subject: r.subject,
            grade: r.grade,
            resourceType: r.type.name,
            isInitiallySaved: _savedStatuses[r.id] ?? false,
          ),
        ),
      ),
      child: Container(
        width: 160.w,
        padding: EdgeInsets.all(AppSpacing.md.w),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 14.sp, color: cs.primary),
                SizedBox(width: AppSpacing.xs.w),
                Expanded(
                  child: Text(r.type.name.toUpperCase(),
                      style: tt.labelSmall?.copyWith(
                          fontWeight: AppSpacing.weightStrong,
                          color: cs.primary),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            SizedBox(height: AppSpacing.sm.h),
            Text(r.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: tt.titleSmall?.copyWith(
                    color: cs.onSurface)),
            const Spacer(),
            Row(
              children: [
                Icon(Icons.school_outlined, size: 12.sp,
                    color: cs.onSurfaceVariant),
                SizedBox(width: AppSpacing.xs.w),
                Text(r.grade,
                    style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<ResourceModel> _computeRecommendations() {
    if (_allResources.isEmpty) return [];
    final downloadedOrSaved = <String>{..._downloadedIds};
    for (final id in _savedStatuses.keys) {
      if (_savedStatuses[id] == true) downloadedOrSaved.add(id.toString());
    }
    final candidateIds = <String>{};
    final String? myGrade = widget.initialGrade.isNotEmpty ? widget.initialGrade : null;
    final subjects = <String>{};
    for (final r in _allResources) {
      if (downloadedOrSaved.contains(r.id)) {
        subjects.add(r.subject);
      }
    }
    final scored = <_ScoredResource>[];
    for (final r in _allResources) {
      final id = r.id;
      if (downloadedOrSaved.contains(id) || candidateIds.contains(id)) continue;
      int score = 0;
      if (myGrade != null && r.grade == myGrade) score += 3;
      if (subjects.contains(r.subject)) score += 2;
      if (downloadedOrSaved.isNotEmpty) {
        final favType = _mostFrequentType();
        if (favType != null && r.type == favType) score += 1;
      }
      if (score > 0) {
        scored.add(_ScoredResource(r, score));
        candidateIds.add(id);
      }
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(6).map((s) => s.resource).toList();
  }

  ResourceType? _mostFrequentType() {
    final counts = <ResourceType, int>{};
    for (final id in _downloadedIds) {
      final r = _allResources.where((r) => r.id == id).firstOrNull;
      if (r != null) counts[r.type] = (counts[r.type] ?? 0) + 1;
    }
    for (final entry in _savedStatuses.entries) {
      if (entry.value) {
        final r = _allResources.where((r) => r.id == entry.key.toString()).firstOrNull;
        if (r != null) counts[r.type] = (counts[r.type] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return null;
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }
}

class _ScoredResource {
  final ResourceModel resource;
  final int score;
  _ScoredResource(this.resource, this.score);
}