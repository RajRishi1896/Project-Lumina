import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../core/constants/lumina_colors.dart';

class KiwixView extends StatefulWidget {
  final String initialUrl;

  const KiwixView({
    super.key,
    required this.initialUrl,
  });

  @override
  State<KiwixView> createState() => _KiwixViewState();
}

class _KiwixViewState extends State<KiwixView> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(LuminaColors.surface)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (_) => setState(() => _isLoading = false),
          onWebResourceError: (error) {
            debugPrint('Webview Error: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'KNOWLEDGE BASE',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                letterSpacing: 1.5,
                fontWeight: FontWeight.w800,
              ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: LuminaColors.primaryDeepBlue),
            onPressed: () => _controller.reload(),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(
                color: LuminaColors.saffron,
              ),
            ),
        ],
      ),
    );
  }
}
