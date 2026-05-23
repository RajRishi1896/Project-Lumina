import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:edumesh_android/core/models/resource_model.dart';
import 'package:edumesh_android/shared/services/mock_data_service.dart' hide ResourceModel;
import 'package:edumesh_android/shared/services/save_resource_service.dart';

// Assuming you have a real service class, if not, create a placeholder
class MyRealDatabaseService {
  static List<dynamic> getAllResources() => []; 
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  // MOVED: demoData inside the State class so it is accessible
  final int demoData = 0; 
  
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  List<Map<String, dynamic>> _searchIndex = [];
  // ADDED: Missing list for your refresh logic
  List<dynamic> _savedResources = [];

  @override
  void initState() {
    super.initState();
    _searchIndex = _fetchLiveResources();
    _refreshSavedResources(); 
  }

  void _refreshSavedResources() async {
    // Added 'async' because SaveResourceService methods are usually Future-based
    final results = await SaveResourceService.getAllSavedResources();
    if (mounted) {
      setState(() {
        _savedResources = results;
      });
    }
  }

  List<Map<String, dynamic>> _fetchLiveResources() {
    final List<Map<String, dynamic>> globalSearchIndex = [];
    try {
      final List<dynamic> resources = demoData == 0 
          ? MockDataService.getResources() 
          : MyRealDatabaseService.getAllResources();
          
      for (var resource in resources) {
        globalSearchIndex.add({
          "title": resource.title ?? "Untitled",
          "searchKeywords": "${resource.title} ${resource.subject} ${resource.grade} ${resource.type}".toLowerCase(),
          "originalObject": resource,
        });
      }
    } catch (e) {
      debugPrint("Search index error: $e");
    }
    return globalSearchIndex;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filteredResults = _searchIndex.where((item) {
      if (_searchQuery.trim().isEmpty) return false;
      return (item["searchKeywords"] as String).contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: cs.surface,
        iconTheme: IconThemeData(color: cs.primary),
        title: Text("Search Resources", style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800, fontSize: 20.sp)),
      ),
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(16.r), border: Border.all(color: cs.outlineVariant)),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _searchQuery = value),
                style: TextStyle(color: cs.onSurface),
                decoration: InputDecoration(icon: Icon(Icons.search_rounded, color: cs.onSurfaceVariant), hintText: "Search by title, subject, or grade...", border: InputBorder.none),
              ),
            ),
            SizedBox(height: 16.h),
            Expanded(
              child: _searchQuery.trim().isEmpty
                  ? Center(child: Text("Start typing to search...", style: TextStyle(color: cs.onSurfaceVariant)))
                  : filteredResults.isEmpty
                      ? Center(child: Text("No results found.", style: TextStyle(color: cs.onSurfaceVariant)))
                      : ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: filteredResults.length,
                          itemBuilder: (context, index) {
                            final item = filteredResults[index];
                            final dynamic original = item["originalObject"];

                            return Card(
                              color: cs.surfaceContainer,
                              margin: EdgeInsets.only(bottom: 10.h),
                              child: FutureBuilder<bool>(
                                future: SaveResourceService.isSaved(original.id),
                                builder: (context, snapshot) {
                                  bool isSaved = snapshot.data ?? false;
                                  return ListTile(
                                    title: Text(item["title"], style: TextStyle(color: cs.onSurface)),
                                    trailing: IconButton(
                                      icon: Icon(isSaved ? Icons.bookmark : Icons.bookmark_border, color: cs.primary),
                                      onPressed: () async {
                                        await SaveResourceService.toggleSaveStatus(original.id);
                                        setState(() {});
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isSaved ? "Removed from Saved" : "Added to Saved"), duration: const Duration(milliseconds: 600)));
                                        }
                                      },
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}