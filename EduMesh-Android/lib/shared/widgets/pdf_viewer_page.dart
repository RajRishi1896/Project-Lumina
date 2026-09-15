import 'dart:async';
import 'package:edumesh_android/core/navigation/lumina_transitions.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:pdfx/pdfx.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/network/api_client.dart';
import '../../../core/constants/app_spacing.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';
import '../../core/services/activity_tracker.dart';

/// A full-screen PDF viewer page with pinch-to-zoom and page navigation.
///
/// Supports both local file paths and remote URLs (fetched via [ApiClient]).
/// The last-viewed page is persisted to [SharedPreferences] and restored on
/// subsequent opens. Zoom and page-jump controls are displayed as an
/// overlay that toggles on tap.
class PdfViewerPage extends StatefulWidget {
  final String title;

  /// The PDF source path or URL.
  ///
  /// When the value starts with `http` or `/files/`, the PDF bytes are
  /// fetched through [ApiClient]. Otherwise it is treated as a local file path.
  final String pdfUrl;

  /// The subject associated with this resource, passed to activity tracking.
  final String? subject;

  /// Called exactly once when the last page is reached.
  final VoidCallback? onLastPage;

  const PdfViewerPage({
    super.key,
    required this.title,
    required this.pdfUrl,
    this.subject,
    this.onLastPage,
  });

  @override
  State<PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<PdfViewerPage> {
  late PdfControllerPinch _pdfController;
  int _currentPage = 1;
  int _totalPages = 0;
  double _zoomLevel = 1.0;
  bool _controlsVisible = true;
  bool _loaded = false;
  bool _docError = false;
  bool _disposed = false;
  bool _lastPageFired = false;
  int? _pendingRestorePage;
  Timer? _savePositionDebounce;

  String get _positionKey => 'pdf_pos_${widget.pdfUrl}';

  Future<PdfDocument> _openPdf() async {
    if (widget.pdfUrl.startsWith('http') || widget.pdfUrl.startsWith('/files/')) {
      final cacheFile = await _getCachedPdfFile();
      if (await cacheFile.exists()) {
        return PdfDocument.openFile(cacheFile.path);
      }
      await ApiClient.ensureInitialized();
      final response = await ApiClient.dio.get(
        widget.pdfUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      await cacheFile.writeAsBytes(response.data as List<int>, flush: true);
      unawaited(_prunePdfCache());
      return PdfDocument.openData(response.data);
    }
    return PdfDocument.openFile(widget.pdfUrl);
  }

  /// FNV-1a over the full URL: deterministic across restarts, and distinct
  /// URLs never collide (the old regex-to-'_' scheme collapsed
  /// `/files/a_b.pdf` and `/files/a.b.pdf` onto one cache file).
  String get _cacheKey {
    var hash = 0xcbf29ce484222325;
    for (final unit in widget.pdfUrl.codeUnits) {
      hash ^= unit;
      hash *= 0x100000001b3;
    }
    return 'fnv1a_${hash.toRadixString(16)}';
  }

  Future<File> _getCachedPdfFile() async {
    final dir = await getTemporaryDirectory();
    return File('${dir.path}/pdf_cache_$_cacheKey');
  }

  /// Caps the view-time PDF cache at [_maxPdfCacheFiles] by deleting the
  /// oldest entries. Browsing many PDFs must not grow the app unboundedly.
  static const int _maxPdfCacheFiles = 12;

  Future<void> _prunePdfCache() async {
    try {
      final dir = await getTemporaryDirectory();
      final files = <File>[];
      await for (final entry in dir.list()) {
        if (entry is File && entry.path.contains('pdf_cache_')) files.add(entry);
      }
      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      if (files.length > _maxPdfCacheFiles) {
        for (final stale in files.skip(_maxPdfCacheFiles)) {
          try { await stale.delete(); } catch (_) {}
        }
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    ActivityTracker().startStudySession(subject: widget.subject);
    _pdfController = PdfControllerPinch(document: _openPdf());
    _pdfController.addListener(_onPageChanged);
    _restorePosition();
  }

  Future<void> _restorePosition() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt(_positionKey);
    if (saved == null || saved <= 1 || _disposed) return;
    _pendingRestorePage = saved;
    _applyPendingRestore();
  }

  /// Applies the saved page once [PdfControllerPinch.pagesCount] is known,
  /// clamped so a stale saved value can never address past the last page.
  void _applyPendingRestore() {
    final target = _pendingRestorePage;
    final total = _pdfController.pagesCount;
    if (target == null || total == null || _disposed) return;
    _pendingRestorePage = null;
    final page = target.clamp(1, total);
    if (page > 1) {
      unawaited(
          _pdfController.animateToPage(pageNumber: page, duration: Duration.zero));
    }
  }

  Future<void> _savePosition(int page) async {
    if (_disposed) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_positionKey, page);
  }

  void _onPageChanged() {
    if (_disposed) return;
    _applyPendingRestore();
    final page = _pdfController.page;
    final total = _pdfController.pagesCount ?? _totalPages;
    final zoom = _pdfController.value.getMaxScaleOnAxis();
    final pageChanged = page > 0 && page != _currentPage;
    final zoomChanged = (zoom - _zoomLevel).abs() > 0.01;
    if (pageChanged || total != _totalPages || !_loaded || zoomChanged) {
      setState(() {
        if (page > 0) {
          _currentPage = page;
          _totalPages = total;
          _loaded = true;
        }
        if (zoomChanged) _zoomLevel = zoom;
      });
      if (pageChanged) {
        _savePositionDebounce?.cancel();
        _savePositionDebounce = Timer(const Duration(milliseconds: 400), () {
          _savePosition(page);
        });
      }
      // Exact completion signal: last page reached.
      if (!_lastPageFired && _totalPages > 0 && _currentPage >= _totalPages) {
        _lastPageFired = true;
        try {
          widget.onLastPage?.call();
        } catch (_) {}
      }
    }
  }

  void _setZoom(double newZoom) {
    newZoom = newZoom.clamp(0.5, 5.0);
    final m = _pdfController.value.clone()
      ..setEntry(0, 0, newZoom)
      ..setEntry(1, 1, newZoom);
    _pdfController.value = m;
    setState(() => _zoomLevel = newZoom);
  }

  void _showPagePicker() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: _currentPage.toString());
    showLuminaDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cs.surfaceContainerHighest,
        title: Text(l10n.pdfPageOfLabel(_currentPage, _totalPages),
            style: tt.titleLarge?.copyWith(color: cs.onSurface)),
        content: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.sizeOf(context).height * 0.5,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      style: tt.bodyLarge?.copyWith(color: cs.onSurface),
                      decoration: InputDecoration(
                        labelText: l10n.pdfEnterPageNumberHint,
                        filled: true,
                        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ElevatedButton(
                    onPressed: () {
                      final p = int.tryParse(controller.text);
                      if (p != null && p >= 1 && p <= _totalPages) {
                        Navigator.pop(ctx);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _pdfController.animateToPage(pageNumber: p);
                        });
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.onPrimary,
                      foregroundColor: cs.primary,
                    ),
                    child: Text(l10n.pdfGoButton),
                  ),
                ],
              ),
              SizedBox(height: AppSpacing.lg.h),
              Expanded(
                child: GridView.builder(
                  shrinkWrap: true,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6,
                    childAspectRatio: 1.2,
                    crossAxisSpacing: AppSpacing.xs,
                    mainAxisSpacing: AppSpacing.xs,
                  ),
                  itemCount: _totalPages,
                  itemBuilder: (_, i) {
                    final p = i + 1;
                    final isCurrent = p == _currentPage;
                    return Material(
                      color: isCurrent ? cs.onPrimary : cs.surfaceContainerHighest.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                        onTap: () {
                          Navigator.pop(ctx);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _pdfController.animateToPage(pageNumber: p);
                          });
                        },
                        child: Center(
                          child: Text(
                            p.toString(),
                            style: tt.labelSmall?.copyWith(
                              color: isCurrent ? cs.onPrimary : cs.onSurfaceVariant,
                              fontWeight: isCurrent ? AppSpacing.weightStrong : AppSpacing.weightBody,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() => controller.dispose());
  }

  /// Recreates the document future after a load failure so Retry gets a
  /// fresh attempt instead of replaying the same failed Future.
  void _retryLoad() {
    _lastPageFired = false;    setState(() {
      _docError = false;
      _loaded = false;
      _currentPage = 1;
      _totalPages = 0;
    });
    _pdfController.removeListener(_onPageChanged);
    _pdfController.dispose();
    _pdfController = PdfControllerPinch(document: _openPdf());
    _pdfController.addListener(_onPageChanged);
  }

  @override
  void dispose() {
    _disposed = true;
    ActivityTracker().endStudySession();
    _savePositionDebounce?.cancel();
    _pdfController.removeListener(_onPageChanged);
    _pdfController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: cs.surfaceContainerHighest,
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: cs.surfaceContainerHighest,
        foregroundColor: cs.onSurface,
        actions: [
          if (_loaded && _totalPages > 0)
            Tooltip(
              message: l10n.pdfTapToJumpLabel,
              child: GestureDetector(
                onTap: _showPagePicker,
                child: Container(
                  margin: EdgeInsets.only(right: AppSpacing.md.w),
                  constraints: const BoxConstraints(minHeight: AppSpacing.touchTarget),
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.md.w),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                  ),
                  child: Text(l10n.pdfPageOfLabel(_currentPage, _totalPages),
                      style: tt.bodySmall?.copyWith(color: cs.onSurface)),
                ),
              ),
            ),
        ],
      ),
      body: GestureDetector(
        onTap: () => setState(() => _controlsVisible = !_controlsVisible),
        child: Stack(
          children: [
            if (_docError)
              Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.section.w),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 48.sp, color: cs.error),
                      SizedBox(height: AppSpacing.md.h),
                      Text(l10n.fileNotAvailable,
                          textAlign: TextAlign.center,
                          style: tt.bodyLarge?.copyWith(color: cs.onSurface)),
                      SizedBox(height: AppSpacing.lg.h),
                      IconButton.filled(
                        onPressed: _retryLoad,
                        icon: const Icon(Icons.refresh),
                        tooltip: l10n.buttonRetry,
                      ),
                    ],
                  ),
                ),
              )
            else
              PdfViewPinch(
                controller: _pdfController,
                onDocumentError: (_) {
                  if (mounted) setState(() => _docError = true);
                },
              ),
            // Loading overlay until the first page renders.
            if (!_loaded && !_docError)
              Container(
                color: cs.surfaceContainerHighest,
                child: const Center(child: CircularProgressIndicator()),
              ),
            if (_controlsVisible && !_docError) ...[
              if (_totalPages > 1)
                Positioned(
                  left: AppSpacing.md.w,
                  right: AppSpacing.md.w,
                  bottom: AppSpacing.md.h,
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                    ),
                    padding: EdgeInsets.fromLTRB(AppSpacing.sm.w, AppSpacing.xs.h, AppSpacing.sm.w, AppSpacing.sm.h),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              tooltip: l10n.quizPrevious,
                              icon: Icon(Icons.chevron_left, color: cs.onSurface),
                              onPressed: _currentPage > 1
                                  ? () => _pdfController.animateToPage(pageNumber: _currentPage - 1)
                                  : null,
                            ),
                            Tooltip(
                              message: l10n.pdfTapToJumpLabel,
                              child: GestureDetector(
                                onTap: _showPagePicker,
                                child: Container(
                                  constraints: const BoxConstraints(minHeight: AppSpacing.touchTarget),
                                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm.w),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHighest.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                                  ),
                                  child: Text(l10n.pdfPageOfLabel(_currentPage, _totalPages),
                                      style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Slider(
                                value: _currentPage.toDouble(),
                                min: 1,
                                max: _totalPages.toDouble(),
                                activeColor: cs.primary,
                                inactiveColor: cs.outline,
                                onChanged: (v) {
                                  _pdfController.animateToPage(pageNumber: v.round(), duration: Duration.zero);
                                },
                              ),
                            ),
                            IconButton(
                              tooltip: l10n.quizNext,
                              icon: Icon(Icons.chevron_right, color: cs.onSurface),
                              onPressed: _currentPage < _totalPages
                                  ? () => _pdfController.animateToPage(pageNumber: _currentPage + 1)
                                  : null,
                            ),
                          ],
                        ),
                        GestureDetector(
                          onTap: _showPagePicker,
                          child: Container(
                            constraints: const BoxConstraints(minHeight: AppSpacing.touchTarget),
                            padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm.w),
                            alignment: Alignment.center,
                            child: Text(l10n.pdfTapToJumpLabel,
                                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Positioned(
                right: AppSpacing.lg,
                top: AppSpacing.lg,
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.add, color: cs.onSurface),
                        onPressed: () => _setZoom(_zoomLevel + 0.25),
                      ),
                      Text(l10n.pdfZoomPercent((_zoomLevel * 100).toInt().toString()),
                          style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                      IconButton(
                        icon: Icon(Icons.remove, color: cs.onSurface),
                        onPressed: () => _setZoom(_zoomLevel - 0.25),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
