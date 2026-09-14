import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';
import '../../../core/constants/lumina_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/services/activity_tracker.dart';
import '../../../core/network/api_client.dart';
/// A full-screen WebView wrapper for displaying Kiwix / ZIM content.
///
/// Accepts either an [initialUrl], [initialHtml], or a [filePath] to load.
/// At least one must be provided. [filePath] is preferred for saved articles
/// because the WebView resolves relative asset paths from the file's directory.
class KiwixView extends StatefulWidget {
  /// A remote URL to load in the WebView.
  final String? initialUrl;

  /// An HTML string to render directly in the WebView.
  final String? initialHtml;

  /// A local file path to load in the WebView.
  /// When set, relative asset paths in the HTML resolve from the file's
  /// directory — no base64 inlining needed.
  final String? filePath;

  /// An optional title shown in the app bar.
  final String? title;

  /// Base URL for resolving relative asset paths in [initialHtml].
  /// Required when [initialHtml] contains rewritten `/zim/asset` URLs.
  final String? baseUrl;

  /// Subject associated with the content, passed to activity tracking.
  final String? subject;

  const KiwixView({
    super.key,
    this.initialUrl,
    this.initialHtml,
    this.filePath,
    this.title,
    this.baseUrl,
    this.subject,
  }) : assert(initialUrl != null || initialHtml != null || filePath != null,
            'One of initialUrl, initialHtml, or filePath must be provided');

  /// Creates the state for the [KiwixView].
  @override
  State<KiwixView> createState() => _KiwixViewState();
}

class _KiwixViewState extends State<KiwixView> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String? _errorMessage;

  /// Set once the file:// load has been abandoned for the in-memory
  /// fallback, so a second main-frame failure cannot loop forever.
  bool _stringFallbackUsed = false;

  @override
  void initState() {
    super.initState();
    ActivityTracker().startStudySession(subject: widget.subject);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(LuminaColors.surface)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _isLoading = true;
              _errorMessage = null;
            });
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _errorMessage = null;
            });
          },
          onWebResourceError: (error) {
            // Sub-frame failures (a blocked image, a stray script) must not
            // replace the whole article with the error screen. NOTE: check
            // `== false`, not `!= true`: on some Android WebView versions
            // isForMainFrame arrives null, and the old check silently
            // swallowed real main-frame failures behind the naked system
            // error page.
            if (error.isForMainFrame == false) return;
            if (!mounted) return;
            // The file this page was opened from may be unreadable through
            // file:// on this device even though it exists on disk. Fall
            // back once to rendering the bytes directly so the article
            // still opens (relative asset links may degrade instead).
            if (widget.filePath != null && !_stringFallbackUsed) {
              _stringFallbackUsed = true;
              unawaited(_loadFileAsString(widget.filePath!));
              return;
            }
            setState(() {
              _isLoading = false;
              _errorMessage = error.description;
            });
            debugPrint('Webview Error: ${error.description}');
          },
        ),
      );

    _loadInitial();
  }

  /// Opens the initial source, verifying local files exist first so a
  /// missing file shows our error UI instead of the system error page.
  Future<void> _loadInitial() async {
    if (widget.filePath != null) {
      try {
        if (!await File(widget.filePath!).exists()) {
          if (!mounted) return;
          final l10n = AppLocalizations.of(context)!;
          setState(() {
            _isLoading = false;
            _errorMessage = l10n.zimArticleNotFound;
          });
          return;
        }
      } catch (_) {
        // Existence check itself failed: let loadFile try anyway; its
        // error path handles failure with the fallback above.
      }
      unawaited(_controller.loadFile(widget.filePath!));
    } else if (widget.initialHtml != null) {
      final base = widget.baseUrl ?? ApiClient.baseUrl;
      unawaited(_controller.loadHtmlString(widget.initialHtml!, baseUrl: base));
    } else if (widget.initialUrl != null) {
      unawaited(_controller.loadRequest(Uri.parse(widget.initialUrl!)));
    }
  }

  /// Reads a saved article file and renders its bytes directly. Used once
  /// when the file:// load of the same path fails on-device.
  Future<void> _loadFileAsString(String path) async {
    try {
      final html = await File(path).readAsString();
      if (!mounted || html.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage =
                AppLocalizations.of(context)!.zimArticleNotFound;
          });
        }
        return;
      }
      await _controller.loadHtmlString(html);
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = AppLocalizations.of(context)!.zimArticleNotFound;
        });
      }
    }
  }

  @override
  void dispose() {
    ActivityTracker().endStudySession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: l10n.tooltipBackToResource,
          icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.title ?? l10n.kiwixDefaultTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                letterSpacing: 1.5,
                fontWeight: AppSpacing.weightDisplay,
              ),
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: l10n.errorRetryButton,
            icon: const Icon(Icons.refresh, color: LuminaColors.primaryDeepBlue),
            onPressed: () {
              setState(() {
                _errorMessage = null;
                _isLoading = true;
                _stringFallbackUsed = false;
              });
              unawaited(_loadInitial());
            },
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
          if (_errorMessage != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _errorMessage = null;
                          _isLoading = true;
                          _stringFallbackUsed = false;
                        });
                        unawaited(_loadInitial());
                      },
                      child: Text(l10n.errorRetryButton),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
