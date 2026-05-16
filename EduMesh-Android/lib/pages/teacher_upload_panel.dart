import 'package:flutter/material.dart';
import '../core/network/api_client.dart';
import '../shared/widgets/lumina_settings_sheet.dart';

class TeacherUploadPanel extends StatefulWidget {
  const TeacherUploadPanel({super.key});

  @override
  State<TeacherUploadPanel> createState() => _TeacherUploadPanelState();
}

class _TeacherUploadPanelState extends State<TeacherUploadPanel> {
  Future<List<Map<String, dynamic>>> _fetchServerFiles() async {
    try {
      final resp = await ApiClient.get('/files');
      if (resp.data is List) return List<Map<String, dynamic>>.from(resp.data);
      return [];
    } catch (e) {
      return Future.error(e);
    }
  }

  void _openServerFileManager() async {
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) {
      return SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Server Files', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<List<Map<String,dynamic>>>(
                  future: _fetchServerFiles(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                    if (snap.hasError) return Center(child: Text('Error fetching files: ${snap.error}'));
                    final files = snap.data ?? [];
                    if (files.isEmpty) return const Center(child: Text('No files available on server'));
                    return ListView.separated(
                      itemCount: files.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final f = files[i];
                        final name = f['name'] ?? 'unknown';
                        final size = f['size'] ?? 0;
                        return ListTile(
                          title: Text(name),
                          subtitle: Text('${(size/1024).toStringAsFixed(1)} KB'),
                          trailing: ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Selected: $name')));
                              // TODO: trigger download or import flow
                            },
                            child: const Text('Upload'),
                          ),
                        );
                      },
                    );
                  },
                ),
              )
            ],
          ),
        ),
      );
    });
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => const LuminaSettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Teacher Upload Panel')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    flex: 2,
                    child: Container(
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Student Portal', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF002045))),
                          const SizedBox(height: 8),
                          const Text('Offline Mode Active', style: TextStyle(color: Color(0xFF111c2c))),
                          const SizedBox(height: 16),
                          Expanded(child: _SidebarNav(onSettingsTap: () => _showSettings(context))),
                          const SizedBox(height: 8),
                          ElevatedButton(onPressed: () {}, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF13696a)), child: const Text('Check Updates'))
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 5,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Storage Capacity', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), Row(children: const [Icon(Icons.sync), SizedBox(width: 8), Icon(Icons.signal_wifi_4_bar)])]),
                          const SizedBox(height: 12),
                          Container(height: 120, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)), padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [Text('12.4 GB used'), SizedBox(height: 8), LinearProgressIndicator(value: 0.19)])),
                          const SizedBox(height: 16),
                          _FoldersGrid(),
                          const SizedBox(height: 20),
                          // Upload area with single Upload button
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300), color: Colors.grey.shade50),
                            child: Column(
                              children: [
                                const Icon(Icons.upload_file, size: 48, color: Color(0xFF002045)),
                                const SizedBox(height: 8),
                                const Text('Upload Files', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                const Text('Tap Upload to open the server file manager and select files to import.', textAlign: TextAlign.center),
                                const SizedBox(height: 12),
                                ElevatedButton(
                                  onPressed: _openServerFileManager,
                                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF13696a)),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 18.0, vertical: 12.0),
                                    child: Text('Upload', style: TextStyle(fontSize: 16)),
                                  ),
                                )
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          _FileManifestTable(),
                        ],
                      ),
                    ),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _SidebarNav extends StatelessWidget {
  final VoidCallback onSettingsTap;
  const _SidebarNav({required this.onSettingsTap});

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      itemExtent: 56, // Hardened height
      children: [
        const ListTile(leading: Icon(Icons.library_books), title: Text('Library')),
        const ListTile(leading: Icon(Icons.school), title: Text('Courses')),
        const ListTile(leading: Icon(Icons.bookmark), title: Text('Saved')),
        const ListTile(leading: Icon(Icons.cloud_sync), title: Text('Sync Status')),
        ListTile(
          leading: const Icon(Icons.settings), 
          title: const Text('Settings'),
          onTap: onSettingsTap,
        ),
      ],
    );
  }
}

class _FoldersGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final items = [
      ['Mathematics', '142 files'],
      ['Science_2024', '89 files'],
      ['Lecture_Video', '12 files'],
      ['Resources_Final', '312 files'],
    ];
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 2.0,
      ),
      shrinkWrap: true,
      itemCount: items.length,
      itemBuilder: (context, i) {
        final it = items[i];
        return Container(
          padding: const EdgeInsets.all(12), 
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(8)), 
          child: Row(
            children: [
              const Icon(Icons.folder, color: Color(0xFFffdeaa)), 
              const SizedBox(width: 8), 
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, 
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(it[0], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), 
                    Text(it[1], style: const TextStyle(fontSize: 11))
                  ]
                )
              )
            ]
          )
        );
      },
    );
  }
}

class _FileManifestTable extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final rows = [
      ['Calculus_Module_1.pdf', '4.2 MB', 'Mathematics', 'Synced'],
      ['Cell_Biology_Lecture.mp4', '1.2 GB', 'Lecture_Video', 'Local Only'],
      ['Scientific_Method_Draft.docx', '124 KB', 'Science_2024', 'Synced'],
    ];
    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(8)),
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: rows.length,
        itemExtent: 64, // Hardened height
        itemBuilder: (context, i) {
          final r = rows[i];
          return ListTile(
            title: Text(r[0]),
            subtitle: Text('${r[2]} • ${r[1]}'),
            trailing: Text(r[3]),
          );
        },
      ),
    );
  }
}
