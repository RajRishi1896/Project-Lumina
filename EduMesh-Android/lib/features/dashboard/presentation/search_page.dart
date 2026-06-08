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
import '../../../shared/widgets/resource_thumbnail.dart';
import 'resource_detail_page.dart';
import 'zim_browser_page.dart';

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
  String _searchQuery = "";
  List<Map<String, dynamic>> _searchIndex = [];
  List<ResourceModel> _allResources = [];
  Map<dynamic, bool> _savedStatuses = {};
  Set<String> _downloadedIds = {};
  Set<String> _pendingIds = {};
  final Set<String> _downloadingIds = {};
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
    _buildSearchIndex(resources);
    _applyFilters();
  } catch (_) {
      try {
        final local = await SaveResourceService.getAllSavedResourceModels();
        if (local.isNotEmpty) {
        _allResources = local;
        _buildSearchIndex(local);
        _applyFilters();
        if (mounted) setState(() { _isLoading = false; _loadError = null; });
          return;
        }
      } catch (_) {}
      if (mounted) setState(() => _loadError = 'Could not reach server. No cached resources available.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _buildSearchIndex(List<ResourceModel> resources) {
    _searchIndex = resources.map((r) {
      return {
        "title": r.title,
        "searchKeywords": "${r.title} ${r.subject} ${r.grade} ${r.type.toString().split('.').last}".toLowerCase(),
        "originalObject": r,
      };
    }).toList();
  }

  Future<void> _loadDownloadStatus() async {
    try {
      final ids = await DownloadService().getAllDownloadedIds();
      final pIds = await DownloadService().getAllPendingIds();
      if (mounted) setState(() {
        _downloadedIds = ids;
        _pendingIds = pIds;
      });
    } catch (_) {}
  }

  Future<void> _refreshSavedResources() async {
    final results = await SaveResourceService.getAllSavedResourceModels();
    if (mounted) {
      final savedIds = results.map((r) => r.id).toSet();
      final statusMap = <dynamic, bool>{};
      for (final item in _searchIndex) {
        final original = item["originalObject"];
        statusMap[original.id] = savedIds.contains(original.id.toString());
      }
      setState(() => _savedStatuses = statusMap);
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
        child: CircularProgressIndicator(strokeWidth: 2),
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
        if (isDownloaded) {
          await DownloadService().deleteDownload(resourceId);
          if (mounted) {
            setState(() => _downloadedIds.remove(resourceId));
          }
          messenger.showSnackBar(SnackBar(
            content: const Text("Download removed"),
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
                content: const Text("Added to queue — will download when server is reachable"),
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
                content: const Text("Download complete"),
                duration: const Duration(milliseconds: 600),
              ));
            }
          } catch (e) {
            debugPrint("Download error: $e");
            if (mounted) {
              setState(() => _downloadingIds.remove(resourceId));
            }
            messenger.showSnackBar(SnackBar(
              content: const Text("Download failed"),
              duration: const Duration(milliseconds: 600),
            ));
          }
        }
      },
    );
  }



  Set<String> _getAllGrades() {
    return _searchIndex
        .map((item) => (item["originalObject"].grade ?? '').toString())
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
    final allGrades = _getAllGrades().toList()..sort();

    Set<ResourceType> tempTypes = Set.from(_selectedTypes);
    Set<String> tempGrades = Set.from(_selectedGrades);
    String tempSubject = _subjectFilter;
    String tempSort = _sortBy;

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
                  Text('Filters',
                      style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: AppSpacing.weightStrong,
                          color: cs.onSurface)),
                  SizedBox(height: 16.h),
                  Text('Resource Type',
                      style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: AppSpacing.weightStrong,
                          color: cs.onSurfaceVariant)),
                  SizedBox(height: 8.h),
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
                  SizedBox(height: 16.h),
                  Row(
                    children: [
                      Text('Show:', style: TextStyle(fontSize: 14.sp, fontWeight: AppSpacing.weightStrong, color: cs.onSurfaceVariant)),
                      SizedBox(width: 12.w),
                      ChoiceChip(
                        label: const Text('My Grade'),
                        selected: tempGrades.contains(widget.initialGrade),
                        onSelected: (_) {
                          setSheetState(() {
                            tempGrades.clear();
                            if (widget.initialGrade.isNotEmpty) tempGrades.add(widget.initialGrade);
                          });
                        },
                      ),
                      SizedBox(width: 8.w),
                      ChoiceChip(
                        label: const Text('All Grades'),
                        selected: tempGrades.isEmpty,
                        onSelected: (_) {
                          setSheetState(() => tempGrades.clear());
                        },
                      ),
                    ],
                  ),
                  SizedBox(height: 16.h),
                  Text('Grade',
                      style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: AppSpacing.weightStrong,
                          color: cs.onSurfaceVariant)),
                  SizedBox(height: 8.h),
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
                  SizedBox(height: 16.h),
                  Text('Subject',
                      style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: AppSpacing.weightStrong,
                          color: cs.onSurfaceVariant)),
                  SizedBox(height: 8.h),
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Filter by subject...',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.r)),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12.w, vertical: 10.h),
                    ),
                    controller: TextEditingController(text: tempSubject),
                    onChanged: (v) => tempSubject = v,
                  ),
                  SizedBox(height: 16.h),
                  Text('Sort By',
                      style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: AppSpacing.weightStrong,
                          color: cs.onSurfaceVariant)),
                  SizedBox(height: 8.h),
                  Wrap(
                    spacing: 8.w,
                    runSpacing: 4.h,
                    children: [
                      _sortChip('Title A-Z', 'title_asc', tempSort,
                          (v) => setSheetState(() => tempSort = v)),
                      _sortChip('Title Z-A', 'title_desc', tempSort,
                          (v) => setSheetState(() => tempSort = v)),
                      _sortChip('Type', 'type', tempSort,
                          (v) => setSheetState(() => tempSort = v)),
                      _sortChip('Grade', 'grade', tempSort,
                          (v) => setSheetState(() => tempSort = v)),
                    ],
                  ),
                  SizedBox(height: 24.h),
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
                          },
                          child: const Text('Reset'),
                        ),
                      ),
                      SizedBox(width: 12.w),
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
                          child: const Text('Apply'),
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
    );
  }

  Widget _sortChip(String label, String value, String current,
      void Function(String) onSelected) {
    final selected = current == value;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12.sp)),
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
            return (item["searchKeywords"] as String)
                .contains(_searchQuery.toLowerCase());
          }).toList();

    final List<Map<String, dynamic>> results = textFiltered.where((item) {
      final original = item["originalObject"];
      if (_selectedTypes.isNotEmpty && !_selectedTypes.contains(original.type)) return false;
      if (_selectedGrades.isNotEmpty && !_selectedGrades.contains(original.grade)) return false;
      if (_subjectFilter.isNotEmpty && !(original.subject ?? '').toLowerCase().contains(_subjectFilter.toLowerCase())) return false;
      return true;
    }).toList();

    results.sort((a, b) {
      final oa = a["originalObject"];
      final ob = b["originalObject"];
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

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: cs.surface,
        iconTheme: IconThemeData(color: cs.primary),
        title: Text("Browse Resources",
            style: TextStyle(
                color: cs.primary,
                fontWeight: AppSpacing.weightDisplay,
                fontSize: 20.sp)),
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
                    padding: EdgeInsets.all(32.w),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off_rounded,
                            size: 48.sp, color: cs.error),
                        SizedBox(height: 16.h),
                        Text(_loadError!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cs.onSurfaceVariant)),
                        SizedBox(height: 16.h),
                        FilledButton.tonalIcon(
                          onPressed: _loadResources,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadResources,
                  child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: SizedBox(height: 8.h)),
            SliverToBoxAdapter(
              child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
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
                      style: TextStyle(color: cs.onSurface),
                      decoration: InputDecoration(
                        icon: Icon(Icons.search_rounded,
                            color: cs.onSurfaceVariant),
                        hintText: "Search by title, subject, or grade...",
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 8.w),
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
            SliverToBoxAdapter(child: SizedBox(height: 12.h)),
            if (_hasActiveFilters)
              SliverToBoxAdapter(
                child: Padding(
                padding: EdgeInsets.only(bottom: 8.h),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _sortBy != 'title_asc'
                            ? 'Filters active · Sorted: ${_sortBy.replaceAll('_', ' ')}'
                            : 'Filters active',
                        style: TextStyle(
                            color: cs.primary,
                            fontSize: 13.sp,
                            fontWeight: AppSpacing.weightBody),
                      ),
                    ),
                    TextButton.icon(
                      icon: Icon(Icons.clear_all, size: 16.sp),
                      label: const Text('Clear filters'),
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
                  padding: EdgeInsets.only(top: 16.h, bottom: 8.h),
                  child: Text('All Resources',
                      style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: AppSpacing.weightStrong,
                          color: cs.onSurface)),
                ),
              ),
            _filteredResults.isEmpty
                ? SliverFillRemaining(
                    child: Center(
                    child: Text(
                    _searchQuery.trim().isEmpty && !_hasActiveFilters
                        ? "No resources available on the hub."
                        : "No results found.",
                    style: TextStyle(color: cs.onSurfaceVariant),
                  )))
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = _filteredResults[index];
                        final dynamic original = item["originalObject"];

                          final isKiwix = original.type == ResourceType.kiwix;

                          final isOfflineUnavailable = !ConnectivityService().isOnline && !_downloadedIds.contains(original.id.toString());

                          return Opacity(
                            opacity: isOfflineUnavailable ? 0.45 : 1.0,
                            child: Container(
                              color: isKiwix
                                  ? cs.primaryContainer
                                  : Colors.transparent,
                              child: ListTile(
                            leading: ResourceThumbnail(resource: original, size: 48),
                            onTap: () {
                              if (original.type == ResourceType.kiwix) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const ZimBrowserPage()),
                                );
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
                                if (isKiwix)
                                  Padding(
                                    padding: EdgeInsets.only(right: 8.w),
                                    child: Container(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 6.w, vertical: 2.h),
                                      decoration: BoxDecoration(
                                        color: cs.primary,
                                        borderRadius:
                                            BorderRadius.circular(4.r),
                                      ),
                                      child: Text(
                                        'WIKI',
                                        style: TextStyle(
                                          color: cs.onPrimary,
                                          fontSize: 10.sp,
                                          fontWeight: AppSpacing.weightStrong,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  child: Text(item["title"],
                                      style:
                                          TextStyle(color: cs.onSurface)),
                                ),
                              ],
                            ),
                            trailing: Row(
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
                                            ? "Removed from Saved"
                                            : "Added to Saved"),
                                        duration:
                                            const Duration(milliseconds: 600),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(width: 4),
                                _buildDownloadButton(original, cs),
                              ],
                            ),
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
    final recommended = _computeRecommendations();
    if (recommended.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome_rounded, size: 18.sp, color: cs.primary),
            SizedBox(width: 6.w),
            Text('Recommended for You',
                style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: AppSpacing.weightStrong,
                    color: cs.onSurface)),
          ],
        ),
        SizedBox(height: 8.h),
        SizedBox(
          height: 120.h,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: recommended.length,
            separatorBuilder: (_, __) => SizedBox(width: 10.w),
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
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 14.sp, color: cs.primary),
                SizedBox(width: 4.w),
                Expanded(
                  child: Text(r.type.name.toUpperCase(),
                      style: TextStyle(
                          fontSize: 10.sp,
                          fontWeight: AppSpacing.weightStrong,
                          color: cs.primary),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            SizedBox(height: 6.h),
            Text(r.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: AppSpacing.weightStrong,
                    color: cs.onSurface)),
            const Spacer(),
            Row(
              children: [
                Icon(Icons.school_outlined, size: 12.sp,
                    color: cs.onSurfaceVariant),
                SizedBox(width: 4.w),
                Text(r.grade,
                    style: TextStyle(
                        fontSize: 11.sp, color: cs.onSurfaceVariant)),
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