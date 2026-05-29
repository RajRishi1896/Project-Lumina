import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:pdfx/pdfx.dart';
import '../../../core/network/api_client.dart';

class PdfViewerPage extends StatefulWidget {
  final String title;
  final String pdfUrl;

  const PdfViewerPage({
    super.key,
    required this.title,
    required this.pdfUrl,
  });

  @override
  State<PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<PdfViewerPage> {
  late final PdfControllerPinch _pdfController;

  Future<PdfDocument> _openPdf() async {
    if (widget.pdfUrl.startsWith('http')) {
      final response = await ApiClient.dio.get(
        widget.pdfUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      return PdfDocument.openData(response.data);
    }
    return PdfDocument.openFile(widget.pdfUrl);
  }

  @override
  void initState() {
    super.initState();
    _pdfController = PdfControllerPinch(document: _openPdf());
  }

  @override
  void dispose() {
    _pdfController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: cs.surface,
      ),
      body: PdfViewPinch(
        controller: _pdfController,
        scrollDirection: Axis.vertical,
        onDocumentError: (error) {
          if (mounted) setState(() {});
        },
      ),
    );
  }
}
