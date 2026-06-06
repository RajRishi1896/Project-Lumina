import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../shared/services/zim_api_service.dart';
import '../../../shared/services/zim_cache_service.dart';
import 'kiwix_view.dart';

/// A page that allows searching and browsing Wikipedia articles served by a
/// local Kiwix / ZIM server.
///
/// Displays a search field and a list of articles loaded from
/// [ZimApiService]. Tapping an article opens it in a [KiwixView] with
/// optional offline caching via [ZimCacheService].
class ZimBrowserPage extends StatefulWidget {
  const ZimBrowserPage({super.key});

  /// Creates the state for the [ZimBrowserPage].
  @override
  State<ZimBrowserPage> createState() => _ZimBrowserPageState();
}

class _ZimBrowserPageState extends State<ZimBrowserPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  final ZimApiService _api = ZimApiService();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  bool _showInitialList = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInitialArticles();
  }

  Future<void> _loadInitialArticles() async {
    setState(() { _loading = true; _error = null; });
    try {
      final articles = await _api.listArticles();
      if (mounted) {
        setState(() {
          _results = articles;
          _showInitialList = true;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = 'Failed to load articles: $e'; _loading = false; });
    }
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      _loadInitialArticles();
      return;
    }
    setState(() { _loading = true; _error = null; _showInitialList = false; });
    try {
      final results = await _api.search(query);
      setState(() { _results = results; _loading = false; });
    } catch (e) {
      setState(() { _error = 'Search failed: $e'; _loading = false; });
    }
  }

  Future<void> _openArticle(String articleId, String title) async {
    setState(() => _loading = true);
    try {
      String? html = await ZimCacheService.getPage(articleId);
      if (html == null) {
        final pageData = await _api.fetchPage(articleId);
        html = pageData['html']?.toString() ?? '';
        if (html.isNotEmpty) {
          await ZimCacheService.savePage(articleId, html);
        }
      }
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => KiwixView(
            initialHtml: html,
            title: title,
          ),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load article: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wikipedia'),
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(16.w),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search Wikipedia articles...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _loadInitialArticles();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
              onSubmitted: _search,
            ),
          ),
          if (_loading && _results.isEmpty)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null)
            Padding(
              padding: EdgeInsets.all(16.w),
              child: Text(_error!, style: TextStyle(color: cs.error)),
            ),
          if (_results.isEmpty && !_loading && _error == null)
            Expanded(
              child: Center(
                child: Text(
                  _showInitialList
                      ? 'No articles available on the server'
                      : 'No results found',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            ),
          if (_results.isNotEmpty)
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                itemCount: _results.length,
                itemBuilder: (context, index) {
                  final item = _results[index];
                  final id = item['article_id']?.toString() ?? '';
                  final title = item['title']?.toString() ?? 'Untitled';
                  return Card(
                    margin: EdgeInsets.only(bottom: 8.h),
                    child: ListTile(
                      leading: const Icon(Icons.article),
                      title: Text(title),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openArticle(id, title),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
