import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import '../../../core/constants/lumina_colors.dart';

class PdfView extends StatefulWidget {
  final String path;
  final String title;

  const PdfView({
    super.key,
    required this.path,
    required this.title,
  });

  @override
  State<PdfView> createState() => _PdfViewState();
}

class _PdfViewState extends State<PdfView> {
  late final PdfControllerPinch _pdfController;
  int _totalPages = 0;
  int _currentPage = 0;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _pdfController = PdfControllerPinch(
      document: PdfDocument.openFile(widget.path),
    );
    _pdfController.addListener(_onPdfChanged);
  }

  void _onPdfChanged() {
    final pages = _pdfController.pagesCount;
    final page = _pdfController.page.isFinite ? _pdfController.page.round() : 0;
    if (pages == null) return;
    if (pages != _totalPages || page != _currentPage || !_isReady) {
      setState(() {
        _totalPages = pages;
        _currentPage = page;
        _isReady = true;
      });
    }
  }

  @override
  void dispose() {
    _pdfController.removeListener(_onPdfChanged);
    _pdfController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title.toUpperCase(),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                '${_currentPage + 1} / $_totalPages',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          PdfViewPinch(
            controller: _pdfController,
            scrollDirection: Axis.horizontal,
          ),
          if (!_isReady)
            const Center(
              child: CircularProgressIndicator(
                color: LuminaColors.academicTeal,
              ),
            ),
        ],
      ),
    );
  }
}
