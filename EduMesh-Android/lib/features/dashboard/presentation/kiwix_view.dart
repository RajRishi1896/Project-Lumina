import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';
import '../../../core/constants/lumina_colors.dart';
import '../../../core/constants/app_spacing.dart';

/// A full-screen WebView wrapper for displaying Kiwix / ZIM content.
///
/// Accepts either an [initialUrl] to load remotely or [initialHtml] to render
/// inline. At least one must be provided.
class KiwixView extends StatefulWidget {
  /// A remote URL to load in the WebView.
  final String? initialUrl;

  /// An HTML string to render directly in the WebView.
  final String? initialHtml;

  /// An optional title shown in the app bar.
  final String? title;

  const KiwixView({
    super.key,
    this.initialUrl,
    this.initialHtml,
    this.title,
  }) : assert(initialUrl != null || initialHtml != null,
            'Either initialUrl or initialHtml must be provided');

  /// Creates the state for the [KiwixView].
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
      );

    if (widget.initialHtml != null) {
      _controller.loadHtmlString(widget.initialHtml!);
    } else if (widget.initialUrl != null) {
      _controller.loadRequest(Uri.parse(widget.initialUrl!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title ?? l10n.kiwixDefaultTitle,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                letterSpacing: 1.5,
                fontWeight: AppSpacing.weightDisplay,
              ),
        ),
        backgroundColor: LuminaColors.surface,
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
