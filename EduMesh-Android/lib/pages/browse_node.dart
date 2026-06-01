import 'package:flutter/material.dart';
import '../core/network/api_client.dart';

class BrowseNodePage extends StatefulWidget {
  const BrowseNodePage({super.key});

  @override
  State<BrowseNodePage> createState() => _BrowseNodePageState();
}

class _BrowseNodePageState extends State<BrowseNodePage> {
  List<dynamic> _items = [];
  bool _loading = false;
  String? _error;

  Future<void> _fetch() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final resp = await ApiClient.get('/api/catalog');
      final data = resp.data;
      if (data is List) {
        if (mounted) setState(() => _items = data);
      } else if (data is Map && data['items'] is List) {
        if (mounted) setState(() => _items = data['items']);
      } else {
        if (mounted) setState(() => _error = 'Unexpected catalog format');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to fetch catalog');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Browse Node')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, idx) {
                    final it = _items[idx];
                    final title = (it is Map && it['title'] != null) ? it['title'].toString() : 'Untitled';
                    final subtitle = (it is Map && it['type'] != null) ? it['type'].toString() : '';
                    return ListTile(
                      title: Text(title),
                      subtitle: Text(subtitle),
                      trailing: const Icon(Icons.download),
                      onTap: () {},
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _fetch,
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
