import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
import '../../../core/services/catalog_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../shared/widgets/resource_thumbnail.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';
import 'resource_detail_page.dart';
import 'kiwix_view.dart';
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

  /// Whether to open the filter sheet immediately on page load.
  final bool openFilters;

  /// When true, skip the Scaffold/AppBar wrapper and return only the body
  /// content -- useful for embedding inside another widget.
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

  Future<void> _loadResources() async {
    if (mounted) setState(() { _isLoading = true; _loadError = null; });
    try {
      final resp = await ApiClient.get('/api/catalog');
      final data = resp.data;
      List<ResourceModel> resources = [];
      if (data is List) {
        resources = data.map((j) => ResourceModel.fromJson(j is Map ? Map<String, dynamic>.from(j) : {})).toList();
      } else if (data is Map && data['items'] is List) {
        resources = (data['items'] as List).map((j) => ResourceModel.fromJson(j is Map ? Map<String, dynamic>.from(j) : {})).toList();
      }
      _allResources = resources;

      try {
        final gradesResp = await ApiClient.get('/student/grades').timeout(const Duration(seconds: 5));
        if (gradesResp.data is List) {
          _serverGrades = (gradesResp.data as List)
              .map((g) => (g is Map ? g['name']?.toString() : null) ?? '')
              .where((g) => g.isNotEmpty)
              .cast<String>()
              .toList();
        }
      } catch (_) {}
      try {
        final subjectsResp = await ApiClient.get('/student/subjects').timeout(const Duration(seconds: 5));
        if (subjectsResp.data is List) {
          _serverSubjects = (subjectsResp.data as List)
              .map((s) => (s is Map ? s['name']?.toString() : null) ?? '')
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
          _allResources = rows.map((r) => ResourceModel(
            id: r['resource_id'] as String? ?? '',
            title: r['title'] as String? ?? '',
            subject: r['subject'] as String? ?? '',
            grade: r['grade'] as String? ?? '',
            type: parseResourceType(r['type'] as String? ?? ''),
            pdfUrl: r['pdf_url'] as String?,
          )).toList();
          _zimArticles = [];
          _applyFilters();
          if (mounted) setState(() { _isLoading = false; _loadError = null; });
          return;
        }
      } catch (_) { }
      try {
        final downloadedRows = await DBHelper().getDownloadedResources();
        if (downloadedRows.isNotEmpty) {
          _allResources = downloadedRows.map((r) => ResourceModel(
            id: r['resource_id'] as String? ?? '',
            title: r['title'] as String? ?? '',
            subject: r['subject'] as String? ?? '',
            grade: r['grade'] as String? ?? '',
            type: parseResourceType(r['type'] as String? ?? ''),
            isDownloaded: true,
          )).toList();
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

  Future<bool> _toggleSaveStatus(String id) async {
    try {
      final db = DBHelper();
      final bookmarked = await db.getBookmarkedIds();
      if (bookmarked.contains(id)) {
        await db.removeBookmark(id);
        unawaited(ActivityTracker().logAction('unsave', resourceId: id));
        return false;
      }
      await db.upsertBookmark(id, '', '', '', '');
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

  Future<void> _openZimArticle(String articleId, String title) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    try {
      String? html;
      // Try reading from local file first (offline support)
      try {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/zim_${articleId.replaceAll('/', '_')}.html');
        if (await file.exists()) {
          html = await file.readAsString();
        }
      } catch (_) {}
      // Fall back to SharedPreferences cache
      if (html == null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          html = prefs.getString('zim_page_$articleId');
        } catch (_) {}
      }
      // Fetch from server if not cached locally
      if (html == null) {
        final response = await ApiClient.get('/zim/page', queryParameters: {
          'article_id': articleId,
        }).timeout(const Duration(seconds: 8));
        final pageData = response.data;
        html = pageData?['html']?.toString() ?? '';
        if (html.isNotEmpty) {
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('zim_page_$articleId', html);
          } catch (_) {}
        }
      }
      if (!mounted) return;
      if (html.isNotEmpty) {
        unawaited(RecentResources.record(articleId, title, 'kiwix'));
        unawaited(Navigator.push(context, MaterialPageRoute(
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

  Future<void> _downloadZimArticle(ZimArticle article) async {
    try {
      final res = await ApiClient.get('/zim/page', queryParameters: {
        'article_id': article.articleId,
      }).timeout(const Duration(seconds: 10));
      var html = res.data['html'] as String? ?? '';
      if (html.isEmpty) return;

      // Inline all /zim/asset references as data URIs for full offline support.
      final assetPattern = RegExp(
        r"""(/zim/asset\?archive_id=[^"'&]+&path=([^"'&]+))""",
      );
      final matches = assetPattern.allMatches(html).toList();
      // ponytail: fetch assets concurrently (5 at a time) instead of sequentially.
      // A page with 20 images goes from 20 serial calls to ~4 batches.
      const concurrency = 5;
      for (var i = 0; i < matches.length; i += concurrency) {
        final batch = matches.sublist(i, (i + concurrency).clamp(0, matches.length));
        await Future.wait(batch.map((m) async {
          final fullUrl = m.group(1)!;
          final assetPath = Uri.decodeComponent(m.group(2)!);
          try {
            final assetResp = await ApiClient.get('/zim/asset', queryParameters: {
              'archive_id': article.archiveId,
              'path': assetPath,
            }).timeout(const Duration(seconds: 5));
            if (assetResp.data is List<int>) {
              final bytes = assetResp.data as List<int>;
              final mime = _guessMime(assetPath);
              final b64 = base64Encode(bytes);
              final dataUri = 'data:$mime;base64,$b64';
              html = html.replaceAll(fullUrl, dataUri);
            }
          } catch (_) {
            // Asset fetch failed -- leave URL as-is, WebView may still load it online.
          }
        }));
      }

      // Save self-contained HTML to disk and SharedPreferences.
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/zim_${article.articleId.replaceAll('/', '_')}.html');
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
          action: SnackBarAction(label: l10n.buttonRetry, onPressed: () => _downloadZimArticle(article)),
        ));
      }
    }
  }

  String _guessMime(String path) {
    final ext = path.split('.').last.toLowerCase();
    const mimeMap = {
      'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
      'gif': 'image/gif', 'svg': 'image/svg+xml', 'webp': 'image/webp',
      'css': 'text/css', 'js': 'application/javascript',
      'woff': 'font/woff', 'woff2': 'font/woff2', 'ttf': 'font/ttf',
      'mp4': 'video/mp4', 'webm': 'video/webm',
    };
    return mimeMap[ext] ?? 'application/octet-stream';
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



  Set<String> _getAllGrades() {
    final catalogGrades = _allResources
        .map((r) => r.grade)
        .where((g) => g.isNotEmpty)
        .toSet();
    catalogGrades.addAll(_serverGrades);
    return catalogGrades;
  }

  String _resourceTypeLabel(ResourceType type) {
    switch (type) {
      case ResourceType.textbook: return 'Textbook';
      case ResourceType.videos: return 'Videos';
      case ResourceType.pyq: return 'PYQ';
      case ResourceType.pastPaper: return 'PYQ';
      case ResourceType.kiwix: return 'ZIM';
      case ResourceType.quiz: return 'Quiz';
      case ResourceType.notes: return 'Notes';
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
                    children: ResourceType.values
                        .where((t) => t != ResourceType.pastPaper && t != ResourceType.kiwix)
                        .map((type) {
                      final selected = tempTypes.contains(type);
                      return FilterChip(
                        label: Text(_resourceTypeLabel(type)),
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
    super.dispose();
  }

  int _zimRequestId = 0;

  /// Returns the server-ranked index of a ZIM article for sort stability.
  int _zimArticleIndex(String articleId) {
    for (var i = 0; i < _zimArticles.length; i++) {
      if (_zimArticles[i].articleId == articleId) return i;
    }
    return _zimArticles.length;
  }

  Future<void> _fetchZimResults() async {
    final query = _searchQuery.trim().replaceAll(RegExp(r'\s+'), ' ');
    _zimRequestId++;
    if (query.length < 3 || !ConnectivityService().isOnline) return;
    final myId = _zimRequestId;
    try {
      final result = await ZimSyncService.instance.searchOnServer(query, limit: 30);
      if (myId != _zimRequestId) return;
      _zimArticles = result.articles;
    } catch (_) {}
    if (mounted) _applyFilters();
  }

  void _applyFilters() {
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

    results.sort((a, b) {
      final aZim = a['isZim'] == true;
      final bZim = b['isZim'] == true;
      if (aZim && bZim) {
        // Preserve server-side relevance ranking -- do NOT re-sort alphabetically.
        final ai = _zimArticleIndex(a['articleId'] as String? ?? '');
        final bi = _zimArticleIndex(b['articleId'] as String? ?? '');
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
                      final ZimArticle? zimArticle = item['zimArticle'];

                      final isOfflineUnavailable = !isZim && !ConnectivityService().isOnline && !_downloadedIds.contains(original.id.toString());

                      if (isZim) {
                        return _buildZimResultTile(
                            item, zimArticle, cs, tt, l10n);
                      }
                      final subtitle = [
                        original.subject,
                        original.grade,
                      ].where((s) => s != null && s.toString().trim().isNotEmpty)
                          .map((s) => s.toString())
                          .join(' \u00B7 ');
                      return ResourceCard(
                        resourceId: original.id.toString(),
                        title: (item['title'] as String?) ?? original.title ?? '',
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
                                await _toggleSaveStatus(original.id);
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
                                final base = ApiClient.dio.options.baseUrl.replaceAll(RegExp(r'/api/?$'), '');
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
                                resourceId: original.id.toString(),
                              ),
                            ),
                          );
                        },
                      );
                    },
                    childCount: _filteredResults.length,
                  ),
                ),
        ],
      ),
    ),
    );

    if (widget.embedded) return body;
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
      onTap: () =>
          _openZimArticle(item['articleId'] as String, item['title'] as String),
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
                  : () => _downloadZimArticle(zimArticle),
            ),
          Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        ],
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
            resourceId: r.id.toString(),
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
    final scored = <(ResourceModel, int)>[];
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
        scored.add((r, score));
        candidateIds.add(id);
      }
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.take(6).map((s) => s.$1).toList();
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