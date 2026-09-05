import 'dart:async';
import 'dart:io';
import 'package:edumesh_android/core/navigation/lumina_transitions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:path_provider/path_provider.dart';
import 'package:edumesh_android/core/models/resource_model.dart';
import 'package:edumesh_android/core/models/zim_article_model.dart';
import 'package:edumesh_android/core/constants/lumina_colors.dart';
import 'package:edumesh_android/core/constants/app_spacing.dart';
import 'package:edumesh_android/core/network/api_client.dart';
import 'package:edumesh_android/core/storage/db_helper.dart';
import 'package:edumesh_android/core/utils/file_utils.dart';
import 'package:edumesh_android/shared/services/download_service.dart';
import '../../../core/services/activity_tracker.dart';
import '../../../shared/services/download_queue.dart';
import '../../../shared/services/connectivity_service.dart';
import '../../../shared/services/zim_sync_service.dart';
import '../../../shared/services/zim_download_helper.dart';
import '../../../core/services/catalog_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../shared/widgets/resource_thumbnail.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';
import 'kiwix_view.dart';
import '../../../shared/widgets/pdf_viewer_page.dart';
import '../../../shared/widgets/video_player_page.dart';
import 'quiz_player_page.dart';
import '../../../core/services/recent_resources.dart';

/// A page for browsing, searching, and filtering all available resources.
///
/// Displays a search field with type/grade/subject filters, a recommended-for-you
/// section, and a scrollable list of matching resources. Supports download,
/// bookmarking, and offline queueing.
class SearchPage extends StatefulWidget {
  /// The student's grade, used to pre-select the grade filter and compute
  /// recommendations.
  final String initialGrade;

  final bool openFilters;

  /// When true, skip the Scaffold/AppBar wrapper and return only the body
  /// content: useful for embedding inside another widget.
  final bool embedded;

  const SearchPage({super.key, this.initialGrade = '', this.openFilters = false, this.embedded = false});

  /// Creates the state for the [SearchPage].
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _searchQuery = '';
  List<ResourceModel> _allResources = [];
  Map<dynamic, bool> _savedStatuses = {};
  Set<String> _downloadedIds = {};
  Set<String> _pendingIds = {};
  final Set<String> _downloadingIds = {};
  List<ZimArticle> _zimArticles = [];
  List<Map<String, dynamic>> _filteredResults = [];
  bool _isLoading = true;
  String? _loadError;

  // Filter state
  Set<ResourceType> _selectedTypes = {};
  Set<String> _selectedGrades = {};
  String _subjectFilter = '';
  String _sortBy = 'title_asc';
  List<String> _serverGrades = [];
  List<String> _serverSubjects = [];
  bool get _hasActiveFilters =>
      _selectedTypes.isNotEmpty || _selectedGrades.isNotEmpty || _subjectFilter.isNotEmpty || _sortBy != 'title_asc';

  @override
  void initState() {
    super.initState();
    ConnectivityService().addListener(_onConnectivityChanged);
    _loadResources();
    _refreshSavedResources();
    _loadDownloadStatus();
    if (widget.initialGrade.isNotEmpty) {
      _selectedGrades = {widget.initialGrade};
    }
    if (widget.openFilters) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showFilterSheet());
    }
  }

  void _onConnectivityChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadResources() async {
    if (mounted) setState(() { _isLoading = true; _loadError = null; });
    try {
      final resp = await ApiClient.get('/api/catalog');
      final data = resp.data;
      List<ResourceModel> resources = [];
      if (data is List) {
        resources = data.map((j) => ResourceModel.fromJson(j as Map<String, dynamic>)).toList();
      } else if (data is Map && data['items'] is List) {
        resources = (data['items'] as List).map((j) => ResourceModel.fromJson(j as Map<String, dynamic>)).toList();
      }
      _allResources = resources;

      try {
        final gradesResp = await ApiClient.get('/student/grades').timeout(const Duration(seconds: 5));
        if (gradesResp.data is List) {
          _serverGrades = (gradesResp.data as List)
              .map((g) => (g as Map)['name']?.toString() ?? '')
              .where((g) => g.isNotEmpty)
              .cast<String>()
              .toList();
        }
      } catch (_) {}
      try {
        final subjectsResp = await ApiClient.get('/student/subjects').timeout(const Duration(seconds: 5));
        if (subjectsResp.data is List) {
          _serverSubjects = (subjectsResp.data as List)
              .map((s) => (s as Map)['name']?.toString() ?? '')
              .where((s) => s.isNotEmpty)
              .cast<String>()
              .toList();
        }
      } catch (_) {}

      _zimArticles = [];
      if (_searchQuery.trim().length >= 3) {
        try {
          final zimResult = await ZimSyncService.instance.searchOnServer(_searchQuery.trim(), limit: 50);
          _zimArticles = zimResult.articles;
        } catch (_) { }
      }
      try { _applyFilters(); } catch (_) {}
      unawaited(CatalogService().syncCatalog().catchError((_) {}));
    } catch (_) {
      try {
        final catalog = await CatalogService().getCatalog();
        if (catalog.isNotEmpty) {
          _allResources = catalog;
          _zimArticles = [];
          _applyFilters();
          if (mounted) setState(() { _isLoading = false; _loadError = null; });
          return;
        }
      } catch (_) { }
      try {
        final db = DBHelper();
        final rows = await db.getBookmarkedResources();
        if (rows.isNotEmpty) {
          _allResources = _rowsToModels(rows);
          _zimArticles = [];
          _applyFilters();
          if (mounted) setState(() { _isLoading = false; _loadError = null; });
          return;
        }
      } catch (_) { }
      try {
        final downloadedRows = await DBHelper().getDownloadedResources();
        if (downloadedRows.isNotEmpty) {
          _allResources = _rowsToModels(downloadedRows);
          _zimArticles = [];
          _applyFilters();
          if (mounted) setState(() { _isLoading = false; _loadError = null; });
          return;
        }
      } catch (_) { }
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        setState(() => _loadError = l10n.errorNoServerNoCache);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Maps bookmark/download DB rows to catalog models. Missing columns
  /// (bookmarks carry no local_path, downloads no pdf_url) degrade to null,
  /// which parseResourceType treats identically to omission.
  List<ResourceModel> _rowsToModels(List<Map<String, Object?>> rows) => rows
      .map((r) => ResourceModel(
            id: r['resource_id'] as String? ?? '',
            title: r['title'] as String? ?? '',
            subject: r['subject'] as String? ?? '',
            grade: r['grade'] as String? ?? '',
            type: parseResourceType(r['type'] as String? ?? '',
                filename: r['local_path'] as String?),
            pdfUrl: r['pdf_url'] as String?,
          ))
      .toList();

  Future<void> _loadDownloadStatus() async {
    try {
      final ids = await DBHelper().getDownloadedIds();
      final pIds = await DBHelper().getPendingIds();
      if (mounted) {
        setState(() {
          _downloadedIds = ids;
          _pendingIds = pIds;
        });
      }
    } catch (_) { } }

  Future<bool> _toggleSaveStatus(ResourceModel resource) async {
    try {
      final db = DBHelper();
      final id = resource.id;
      final bookmarked = await db.getBookmarkedIds();
      if (bookmarked.contains(id)) {
        await db.removeBookmark(id);
        unawaited(ActivityTracker().logAction('unsave', resourceId: id));
        return false;
      }
      await db.upsertBookmark(
        id,
        resource.title,
        resource.subject,
        resource.grade,
        resource.type.name,
        pdfUrl: resource.pdfUrl,
      );
      unawaited(ActivityTracker().logAction('save', resourceId: id));
      return true;
    } catch (e) {
      debugPrint('Error toggling bookmark: $e');
      return false;
    }
  }

  Future<void> _refreshSavedResources() async {
    try {
      final savedIds = await DBHelper().getBookmarkedIds();
      if (mounted) {
        final statusMap = <dynamic, bool>{};
        for (final r in _allResources) {
          statusMap[r.id] = savedIds.contains(r.id.toString());
        }
        setState(() => _savedStatuses = statusMap);
      }
    } catch (_) {}
  }

  Future<void> _openArticle(String articleId, String title) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    try {
      // Try new file-based save first (assets as separate files).
      final savedPath = await ZimDownloadHelper.findSavedArticle(articleId);
      if (savedPath != null) {
        if (!mounted) return;
        unawaited(RecentResources.record(articleId, title, 'kiwix'));
        unawaited(Navigator.push(context, luminaRoute(
          builder: (_) => KiwixView(filePath: savedPath, title: title),
        )));
        return;
      }
      // Legacy: single-file fallback.
      String? html;
      try {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/zim_${articleId.replaceAll('/', '_')}.html');
        if (await file.exists()) html = await file.readAsString();
      } catch (_) {}
      if (html == null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          html = prefs.getString('zim_page_$articleId');
        } catch (_) {}
      }
      if (html == null) {
        final response = await ApiClient.get('/zim/page', queryParameters: {
          'article_id': articleId,
        }).timeout(const Duration(seconds: 8));
        html = response.data?['html']?.toString() ?? '';
      }
      if (!mounted) return;
      if (html.isNotEmpty) {
        unawaited(RecentResources.record(articleId, title, 'kiwix'));
        unawaited(Navigator.push(context, luminaRoute(
          builder: (_) => KiwixView(initialHtml: html, title: title, baseUrl: ApiClient.baseUrl),
        )));
      } else {
        messenger.showSnackBar(SnackBar(content: Text(l10n.zimArticleNotFound)));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.zimFailedToLoadArticle(e.toString()))));
      }
    }
  }

  Future<void> _downloadArticle({
    required String articleId,
    required String archiveId,
    String title = '',
  }) async {
    try {
      await ZimDownloadHelper.saveArticle(articleId: articleId, archiveId: archiveId);
      await ZimSyncService.instance.markDownloaded(articleId, title: title);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.snackbarDownloadFailed),
          action: SnackBarAction(label: l10n.buttonRetry, onPressed: () => _downloadArticle(
            articleId: articleId,
            archiveId: archiveId,
            title: title,
          )),
        ));
      }
    }
  }

  Widget _buildDownloadButton(ResourceModel original, ColorScheme cs) {
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

        if (original.type == ResourceType.quiz) {
          _toggleQuizDownload(original, resourceId, messenger, l10n);
          return;
        }

        if (isDownloaded) {
          await DownloadService().deleteDownload(resourceId);
          if (original.type == ResourceType.kiwix) {
            var zimId = original.id;
            if (zimId.startsWith('zim_')) zimId = zimId.substring(4);
            ZimSyncService.instance.unmarkDownloaded(zimId);
          }
          if (mounted) {
            setState(() => _downloadedIds.remove(resourceId));
          }
          messenger.showSnackBar(SnackBar(
            content: Text(l10n.snackbarDownloadRemoved),
            duration: const Duration(milliseconds: 600),
          ));
        } else {
          final base = ApiClient.fileBaseUrl;
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
              action: SnackBarAction(label: l10n.buttonRetry, onPressed: () async {
                await DownloadQueue().enqueue(resourceId, url, fileName,
                  title: original.title, subject: original.subject,
                  grade: original.grade, type: original.type.name,
                );
                if (mounted) setState(() => _pendingIds.add(resourceId));
              }),
            ));
          }
        }
      },
    );
  }

  Future<void> _toggleQuizDownload(
    ResourceModel quiz, String resourceId,
    ScaffoldMessengerState messenger, AppLocalizations l10n,
  ) async {
    if (_downloadedIds.contains(resourceId)) {
      final cacheKey = '${quiz.id}_${quiz.id}';
      await DBHelper().removeCachedQuiz(cacheKey);
      await DBHelper().removeDownload(resourceId);
      if (mounted) setState(() => _downloadedIds.remove(resourceId));
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.snackbarDownloadRemoved),
        duration: const Duration(milliseconds: 600),
      ));
      return;
    }

    setState(() => _downloadingIds.add(resourceId));
    try {
      final resp = await ApiClient.get('/api/quiz-resource/$resourceId')
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200 && resp.data is Map) {
        final cacheKey = '${quiz.id}_${quiz.id}';
        await DBHelper().cacheQuiz(cacheKey, Map<String, dynamic>.from(resp.data));
        await DBHelper().recordQuizDownload(resourceId, quiz.title, quiz.subject, quiz.grade);
        if (mounted) {
          setState(() {
            _downloadingIds.remove(resourceId);
            _downloadedIds.add(resourceId);
          });
        }
        messenger.showSnackBar(SnackBar(
          content: Text(l10n.snackbarDownloadComplete),
          duration: const Duration(seconds: 2),
        ));
      } else {
        if (mounted) setState(() => _downloadingIds.remove(resourceId));
        messenger.showSnackBar(SnackBar(content: Text(l10n.snackbarDownloadFailed)));
      }
    } catch (_) {
      if (mounted) setState(() => _downloadingIds.remove(resourceId));
      messenger.showSnackBar(SnackBar(content: Text(l10n.snackbarDownloadFailed)));
    }
  }



  Set<String> _getAllGrades() {
    final catalogGrades = _allResources
        .map((r) => r.grade)
        .where((g) => g.isNotEmpty)
        .toSet();
    catalogGrades.addAll(_serverGrades);
    return catalogGrades;
  }

  String _resourceTypeLabel(ResourceType type, AppLocalizations l10n) {
    switch (type) {
      case ResourceType.textbook: return l10n.tabTextbooks;
      case ResourceType.videos: return l10n.tabVideos;
      case ResourceType.pyq: return l10n.tabPyqs;
      case ResourceType.pastPaper: return l10n.tabPyqs;
      case ResourceType.kiwix: return l10n.badgeKiwixWiki;
      case ResourceType.quiz: return l10n.tabQuizzes;
      case ResourceType.notes: return l10n.tabNotes;
    }
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

    showLuminaSheet(
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
                AppSpacing.xxl.w, AppSpacing.xxl.h, AppSpacing.xxl.w,
                MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.xxl.h,
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
                    children: ResourceType.values
                        .where((t) => t != ResourceType.pastPaper && t != ResourceType.kiwix)
                        .map((type) {
                      final selected = tempTypes.contains(type);
                      return FilterChip(
                        label: Text(_resourceTypeLabel(type, l10n)),
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
                  Text(l10n.filterGradeHeader,
                      style: tt.titleSmall?.copyWith(
                          color: cs.onSurfaceVariant)),
                  SizedBox(height: AppSpacing.sm.h),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: tempGrades.isEmpty
                        ? ''
                        : tempGrades.contains(widget.initialGrade) && widget.initialGrade.isNotEmpty
                            ? '__my_grade__'
                            : tempGrades.first,
                    items: [
                      DropdownMenuItem(value: '', child: Text(l10n.filterAllGrades)),
                      if (widget.initialGrade.isNotEmpty)
                        DropdownMenuItem(value: '__my_grade__', child: Text(l10n.filterMyGrade)),
                      ...allGrades.map((g) => DropdownMenuItem(value: g, child: Text(g))),
                    ],
                    onChanged: (v) {
                      setSheetState(() {
                        if (v == null || v == '') {
                          tempGrades.clear();
                        } else if (v == '__my_grade__') {
                          tempGrades = {widget.initialGrade};
                        } else {
                          tempGrades = {v};
                        }
                      });
                    },
                  ),
                  SizedBox(height: AppSpacing.lg.h),
                  Text(l10n.filterSubjectHeader,
                      style: tt.titleSmall?.copyWith(
                          color: cs.onSurfaceVariant)),
                  SizedBox(height: AppSpacing.sm.h),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: tempSubject,
                    items: [
                      DropdownMenuItem(value: '', child: Text(l10n.filterSubjectHint)),
                      ...({
                        ..._allResources
                              .map((r) => r.subject)
                              .where((s) => s.isNotEmpty),
                        ..._serverSubjects,
                      }.toList()..sort())
                          .map((s) => DropdownMenuItem(value: s, child: Text(s))),
                    ],
                    onChanged: (v) {
                      setSheetState(() => tempSubject = v ?? '');
                    },
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
    );
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
    _searchDebounce?.cancel();
    _searchController.dispose();
    ConnectivityService().removeListener(_onConnectivityChanged);
    super.dispose();
  }

  int _zimRequestId = 0;

  Future<void> _fetchZimResults() async {
    final query = _searchQuery.trim().replaceAll(RegExp(r'\s+'), ' ');
    _zimRequestId++;
    final myId = _zimRequestId;
    if (!ConnectivityService().isOnline) {
      _zimArticles = [];
      if (mounted) _applyFilters();
      return;
    }
    if (query.length >= 3) {
      try {
        final result = await ZimSyncService.instance.searchOnServer(query, limit: 30);
        if (myId != _zimRequestId) return;
        _zimArticles = result.articles;
      } catch (_) {}
    }
    if (mounted) _applyFilters();
  }

  void _applyFilters() {
    if (!mounted) return;
    final query = _searchQuery.trim().toLowerCase();
    final l10n = AppLocalizations.of(context)!;

    final results = <Map<String, dynamic>>[];
    for (final r in _allResources) {
      if (r.type == ResourceType.kiwix) continue;
      final keywords = '${r.title} ${r.subject} ${r.grade} ${r.type.name}'.toLowerCase();
      if (query.isNotEmpty && !keywords.contains(query)) continue;
      if (_selectedTypes.isNotEmpty) {
        final effectiveType = r.type == ResourceType.pastPaper ? ResourceType.pyq : r.type;
        if (!_selectedTypes.contains(effectiveType)) continue;
      }
      if (_selectedGrades.isNotEmpty && !_selectedGrades.contains(r.grade) && r.grade.isNotEmpty) continue;
      if (_subjectFilter.isNotEmpty && !r.subject.toLowerCase().contains(_subjectFilter.toLowerCase())) continue;
      results.add({'title': r.title, 'originalObject': r, 'isZim': false});
    }
    if (query.length >= 3 && ConnectivityService().isOnline) {
      for (final article in _zimArticles) {
        final title = article.title.isNotEmpty ? article.title : l10n.zimUntitledArticleFallback;
        if (article.articleId.isEmpty) continue;
        results.add({
          'title': title,
          'originalObject': null,
          'isZim': true,
          'articleId': article.articleId,
          'zimArticle': article,
        });
      }
    }

    // Server-ranked index per article id, built once: the sort comparator
    // runs O(n log n) lookups, a linear scan there is O(n·m).
    final zimRank = <String, int>{
      for (var i = 0; i < _zimArticles.length; i++) _zimArticles[i].articleId: i,
    };

    results.sort((a, b) {
      final aZim = a['isZim'] == true;
      final bZim = b['isZim'] == true;
      if (aZim && bZim) {
        // Preserve server-side relevance ranking: do NOT re-sort alphabetically.
        final ai = zimRank[a['articleId']] ?? zimRank.length;
        final bi = zimRank[b['articleId']] ?? zimRank.length;
        return ai.compareTo(bi);
      }
      // When searching, ZIM results (server-ranked) appear first.
      if (aZim) return -1;
      if (bZim) return 1;
      final oa = a['originalObject'];
      final ob = b['originalObject'];
      if (!ConnectivityService().isOnline) {
        final aDl = _downloadedIds.contains(oa.id.toString());
        final bDl = _downloadedIds.contains(ob.id.toString());
        if (aDl != bDl) return aDl ? -1 : 1;
      }
      switch (_sortBy) {
        case 'title_desc': return (ob.title ?? '').compareTo(oa.title ?? '');
        case 'type': return (oa.type?.index ?? 0).compareTo(ob.type?.index ?? 0);
        case 'grade': return (oa.grade ?? '').compareTo(ob.grade ?? '');
        default: return (oa.title ?? '').compareTo(ob.title ?? '');
      }
    });

    if (results.isEmpty && _allResources.isNotEmpty && _hasActiveFilters) {
      _selectedTypes.clear();
      _selectedGrades.clear();
      _subjectFilter = '';
      _sortBy = 'title_asc';
      _applyFilters();
      return;
    }
    setState(() => _filteredResults = results);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;

    final body = _isLoading
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
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
                    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm.h)),
          SliverToBoxAdapter(
            child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) {
      ActivityTracker()
          .logAction('search', metadata: value)
          .catchError((_) {});
      _searchQuery = value;
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          _applyFilters();
          _fetchZimResults();
        }
      });
    },
                    style: tt.bodyLarge?.copyWith(color: cs.onSurface),
                    decoration: InputDecoration(
                      hintText: l10n.searchFieldHint,
                      prefixIcon: Icon(Icons.search_rounded,
                          color: cs.onSurfaceVariant),
                      filled: true,
                      fillColor: cs.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16.r),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg.w,
                          vertical: AppSpacing.md.h),
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                  _searchQuery.trim().isEmpty && !_hasActiveFilters
                      ? l10n.emptyNoResources
                      : l10n.emptyNoSearchResults,
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ))
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = _filteredResults[index];
                      final isZim = item['isZim'] == true;
                      // Typed: `.name` on enums only resolves statically in
                      // this Dart SDK — dynamic dispatch throws NoSuchMethodError.
                      final ResourceModel original =
                          item['originalObject'] as ResourceModel;
                      final ZimArticle? zimArticle = item['zimArticle'];

                      final isOfflineUnavailable = !isZim && !ConnectivityService().isOnline && !_downloadedIds.contains(original.id.toString());

                      if (isZim) {
                        return _buildZimResultTile(item, zimArticle, cs, tt, l10n);
                      }
                      final subtitle = [
                        original.subject,
                        original.grade,
                      ].where((s) => s.toString().trim().isNotEmpty)
                          .map((s) => s.toString())
                          .join(' \u00B7 ');
                      return ResourceCard(
                        resourceId: original.id.toString(),
                        title: (item['title'] as String?) ?? original.title,
                        type: original.type,
                        fileSize: original.fileSize,
                        pageCount: original.pageCount,
                        durationSeconds: original.durationSeconds,
                        subtitle: subtitle.isEmpty ? null : subtitle,
                        isReady: _downloadedIds.contains(original.id.toString()),
                        opacity: isOfflineUnavailable ? 0.45 : 1.0,
                        backgroundColor: isOfflineUnavailable ? cs.surfaceContainerHighest : null,
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
                                await _toggleSaveStatus(original);
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
                        onTap: () {
                          if (isOfflineUnavailable) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(l10n.snackbarNotDownloaded(original.title)),
                              action: SnackBarAction(label: l10n.snackbarQueueAction, onPressed: () {
                                final base = ApiClient.fileBaseUrl;
                                final url = original.pdfUrl ?? '$base/files/${original.id}';
                                final ext = url.contains('.') ? '.${url.split('.').last.split('?').first}' : '.pdf';
                                DownloadQueue().enqueue(original.id.toString(), url, '${original.title}$ext',
                                  title: original.title, subject: original.subject,
                                  grade: original.grade, type: original.type.name,
                                );
                              }),
                            ));
                            return;
                          }
                          unawaited(RecentResources.record(original.id.toString(), original.title, original.type.name));
                          unawaited(ActivityTracker().logAction('view', resourceId: original.id.toString(), metadata: original.title));
                          if (original.type == ResourceType.quiz) {
                            Navigator.push(context, luminaRoute(
                              builder: (_) => QuizPlayerPage.fromResource(original),
                            ));
                          } else if (original.type == ResourceType.videos) {
                            final url = original.pdfUrl?.isNotEmpty == true
                                ? original.pdfUrl!
                                : '${ApiClient.fileBaseUrl}/files/${original.id}';
                            Navigator.push(context, luminaRoute(
                              builder: (_) => VideoPlayerPage(title: original.title, videoUrl: url, subject: original.subject),
                            ));
                          } else {
                            final url = original.pdfUrl?.isNotEmpty == true
                                ? original.pdfUrl!
                                : '${ApiClient.fileBaseUrl}/files/${original.id}';
                            Navigator.push(context, luminaRoute(
                              builder: (_) => PdfViewerPage(title: original.title, pdfUrl: url, subject: original.subject),
                            ));
                          }
                        },
                      );
                    },
                    childCount: _filteredResults.length,
                  ),
                ),
        ],
      ),
    ),
                ),
                ),
    );

    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
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
      body: body,
    );
  }

  Widget _buildZimResultTile(Map<String, dynamic> item, ZimArticle? zimArticle,
      ColorScheme cs, TextTheme tt, AppLocalizations l10n) {
    return ListTile(
      leading: zimArticle != null && zimArticle.hasThumbnail
          ? ClipRRect(
              borderRadius: BorderRadius.circular(6.r),
              child: Image.network(
                '${ApiClient.baseUrl}/zim/thumbnail?article_id=${zimArticle.articleId}',
                width: 48, height: 48, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => CircleAvatar(
                  backgroundColor: cs.primaryContainer,
                  child: Icon(Icons.article, color: cs.primary),
                ),
              ),
            )
          : CircleAvatar(
              backgroundColor: cs.primaryContainer,
              child: Icon(Icons.article, color: cs.primary),
            ),
      onTap: () {
        _openArticle(item['articleId'] as String, item['title'] as String);
      },
      title: Row(
        children: [
          Padding(
            padding: EdgeInsets.only(right: AppSpacing.sm.w),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(4.r),
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
                style: tt.bodyLarge?.copyWith(color: cs.onSurface)),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (zimArticle != null)
            IconButton(
              icon: Icon(
                ZimSyncService.instance.downloadedIds.contains(zimArticle.articleId)
                    ? Icons.check_circle
                    : Icons.download_outlined,
                color: ZimSyncService.instance.downloadedIds.contains(zimArticle.articleId)
                    ? LuminaColors.successGreen
                    : cs.primary,
              ),
              onPressed: ZimSyncService.instance.downloadedIds.contains(zimArticle.articleId)
                  ? null
                  : () => _downloadArticle(
                        articleId: zimArticle.articleId,
                        archiveId: zimArticle.archiveId,
                        title: zimArticle.title,
                      ),
            ),
          Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        ],
      ),
    );
  }
}
