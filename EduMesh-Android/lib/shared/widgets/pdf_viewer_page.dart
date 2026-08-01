import 'dart:async';
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
  /// The display title shown in the app bar.
  final String title;

  /// The PDF source path or URL.
  ///
  /// When the value starts with `http` or `/files/`, the PDF bytes are
  /// fetched through [ApiClient]. Otherwise it is treated as a local file path.
  final String pdfUrl;

  /// The subject associated with this resource, passed to activity tracking.
  final String? subject;

  const PdfViewerPage({
    super.key,
    required this.title,
    required this.pdfUrl,
    this.subject,
  });

  @override
  State<PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<PdfViewerPage> {
  late final PdfControllerPinch _pdfController;
  int _currentPage = 1;
  int _totalPages = 0;
  double _zoomLevel = 1.0;
  bool _controlsVisible = true;
  bool _loaded = false;
  bool _disposed = false;
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
      return PdfDocument.openData(response.data);
    }
    return PdfDocument.openFile(widget.pdfUrl);
  }

  Future<File> _getCachedPdfFile() async {
    final dir = await getTemporaryDirectory();
    final key = widget.pdfUrl.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    return File('${dir.path}/pdf_cache_$key');
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
    if (saved != null && saved > 1) {
      unawaited(_pdfController.animateToPage(pageNumber: saved, duration: Duration.zero));
    }
  }

  Future<void> _savePosition(int page) async {
    if (_disposed) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_positionKey, page);
  }

  void _onPageChanged() {
    if (_disposed) return;
    final page = _pdfController.page;
    final total = _pdfController.pagesCount ?? _totalPages;
    if ((page != _currentPage || total != _totalPages || !_loaded) && page > 0) {
      setState(() {
        _currentPage = page;
        _totalPages = total;
        _loaded = true;
      });
      _savePositionDebounce?.cancel();
      _savePositionDebounce = Timer(const Duration(milliseconds: 400), () {
        _savePosition(page);
      });
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cs.surfaceContainerHighest,
        title: Text(l10n.pdfPageOfLabel(_currentPage, _totalPages),
            style: tt.titleLarge?.copyWith(color: cs.onSurface)),
        content: SizedBox(
          width: double.maxFinite,
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
                        hintText: l10n.pdfEnterPageNumberHint,
                        hintStyle: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
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
                        _pdfController.animateToPage(pageNumber: p);
                        Navigator.pop(ctx);
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
                      borderRadius: BorderRadius.circular(4),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () {
                          _pdfController.animateToPage(pageNumber: p);
                          Navigator.pop(ctx);
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
        title: Text(widget.title),
        backgroundColor: cs.surfaceContainerHighest,
        foregroundColor: cs.onSurface,
        actions: [
          if (_loaded && _totalPages > 0)
            GestureDetector(
              onTap: _showPagePicker,
              child: Container(
                margin: EdgeInsets.only(right: AppSpacing.md.w),
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.md.w, vertical: AppSpacing.sm.h),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(l10n.pdfPageOfLabel(_currentPage, _totalPages),
                    style: tt.bodySmall?.copyWith(color: cs.onSurface)),
              ),
            ),
        ],
      ),
      body: GestureDetector(
        onTap: () => setState(() => _controlsVisible = !_controlsVisible),
        child: Stack(
          children: [
            PdfViewPinch(
              controller: _pdfController,
              onDocumentError: (_) {
                if (mounted) setState(() {});
              },
            ),
            if (_controlsVisible) ...[
              if (_totalPages > 1)
                Positioned(
                  left: AppSpacing.md.w,
                  right: AppSpacing.md.w,
                  bottom: AppSpacing.md.h,
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: EdgeInsets.fromLTRB(AppSpacing.sm.w, AppSpacing.xs.h, AppSpacing.sm.w, AppSpacing.sm.h),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(Icons.chevron_left, color: cs.onSurface),
                              onPressed: _currentPage > 1
                                  ? () => _pdfController.animateToPage(pageNumber: _currentPage - 1)
                                  : null,
                            ),
                            GestureDetector(
                              onTap: _showPagePicker,
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm.w, vertical: AppSpacing.xs.h),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(l10n.pdfPageOfLabel(_currentPage, _totalPages),
                                    style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
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
                            padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm.w, vertical: AppSpacing.xs.h),
                            child: Text(l10n.pdfTapToJumpLabel,
                                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Positioned(
                right: 16,
                top: 16,
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(24),
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
