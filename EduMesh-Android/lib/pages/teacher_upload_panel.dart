import 'package:flutter/material.dart';
import '../core/network/api_client.dart';
import '../shared/widgets/lumina_settings_sheet.dart';

class TeacherUploadPanel extends StatefulWidget {
  const TeacherUploadPanel({super.key});

  @override
  State<TeacherUploadPanel> createState() => _TeacherUploadPanelState();
}

class _TeacherUploadPanelState extends State<TeacherUploadPanel> {
  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _resources = [];
  String _selectedSubjectFilter = 'ALL';
  bool _isLoading = false;

  String? _uiNotificationMessage;
  bool _uiNotificationIsError = false;

  void _showUiNotification(String message, {bool isError = true}) {
    if (!mounted) return;
    setState(() {
      _uiNotificationMessage = message;
      _uiNotificationIsError = isError;
    });
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _uiNotificationMessage == message) {
        setState(() => _uiNotificationMessage = null);
      }
    });
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final subjResp = await ApiClient.get('/subjects');
      final resResp = await ApiClient.get('/resources');
      if (mounted) {
        setState(() {
          _subjects = (subjResp.data is List) ? List<Map<String, dynamic>>.from(subjResp.data) : [];
          _resources = (resResp.data is List) ? List<Map<String, dynamic>>.from(resResp.data) : [];
        });
      }
    } catch (e) {
      debugPrint('Error fetching data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  IconData getSymbolIcon(String symbol) {
    switch (symbol) {
      case 'calculator': return Icons.calculate;
      case 'atom': return Icons.science;
      case 'globe': return Icons.public;
      case 'book': return Icons.book;
      case 'laptop': return Icons.laptop;
      case 'microscope': return Icons.biotech;
      case 'compass': return Icons.architecture;
      case 'code': return Icons.code;
      case 'folder': default: return Icons.folder;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchServerFiles() async {
    try {
      final resp = await ApiClient.get('/files');
      if (resp.data is List) return List<Map<String, dynamic>>.from(resp.data);
      return [];
    } catch (e) {
      return Future.error(e);
    }
  }

  void _showAddSubjectDialog() {
    final nameController = TextEditingController();
    final classController = TextEditingController();
    String selectedSymbol = 'calculator';
    String? dialogError;
    String? dialogSuccess;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add New Subject'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dialogError != null) Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(8), width: double.infinity, decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFF87171))), child: Text(dialogError!, style: const TextStyle(color: Color(0xFF991B1B), fontSize: 13), textAlign: TextAlign.center)),
              if (dialogSuccess != null) Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(8), width: double.infinity, decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFF4ADE80))), child: Text(dialogSuccess!, style: const TextStyle(color: Color(0xFF166534), fontSize: 13), textAlign: TextAlign.center)),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Subject Name', hintText: 'e.g. Biology'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: classController,
                decoration: const InputDecoration(labelText: 'Class/Grade', hintText: 'e.g. Class 10 (or leave blank)'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedSymbol,
                decoration: const InputDecoration(labelText: 'Symbol'),
                items: [
                  DropdownMenuItem(value: 'calculator', child: Row(children: const [Icon(Icons.calculate, color: Color(0xFF13696a)), SizedBox(width: 8), Text('Calculator')])),
                  DropdownMenuItem(value: 'atom', child: Row(children: const [Icon(Icons.science, color: Color(0xFF13696a)), SizedBox(width: 8), Text('Atom')])),
                  DropdownMenuItem(value: 'globe', child: Row(children: const [Icon(Icons.public, color: Color(0xFF13696a)), SizedBox(width: 8), Text('Globe')])),
                  DropdownMenuItem(value: 'book', child: Row(children: const [Icon(Icons.book, color: Color(0xFF13696a)), SizedBox(width: 8), Text('Book')])),
                  DropdownMenuItem(value: 'laptop', child: Row(children: const [Icon(Icons.laptop, color: Color(0xFF13696a)), SizedBox(width: 8), Text('Laptop')])),
                  DropdownMenuItem(value: 'microscope', child: Row(children: const [Icon(Icons.biotech, color: Color(0xFF13696a)), SizedBox(width: 8), Text('Microscope')])),
                  DropdownMenuItem(value: 'compass', child: Row(children: const [Icon(Icons.architecture, color: Color(0xFF13696a)), SizedBox(width: 8), Text('Compass')])),
                  DropdownMenuItem(value: 'code', child: Row(children: const [Icon(Icons.code, color: Color(0xFF13696a)), SizedBox(width: 8), Text('Code')])),
                  DropdownMenuItem(value: 'folder', child: Row(children: const [Icon(Icons.folder, color: Color(0xFF13696a)), SizedBox(width: 8), Text('Folder')])),
                ],
                onChanged: (val) => setDialogState(() => selectedSymbol = val ?? 'calculator'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF13696a)),
              onPressed: () async {
                final name = nameController.text.trim();
                final classVal = classController.text.trim().isNotEmpty ? classController.text.trim() : 'All Classes';
                if (name.isEmpty) {
                  setDialogState(() { dialogSuccess = null; dialogError = 'Please enter a subject name'; });
                  return;
                }
                try {
                  await ApiClient.post('/teacher/subjects', data: {'name': name, 'symbol': selectedSymbol, 'class_name': classVal});
                  _fetchData();
                  setDialogState(() { dialogError = null; dialogSuccess = 'Subject "$name ($classVal)" created'; });
                  Future.delayed(const Duration(seconds: 1), () { if (mounted) Navigator.pop(context); });
                } catch (e) {
                  setDialogState(() { dialogSuccess = null; dialogError = 'Error creating subject: $e'; });
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _showUploadConfigDialog(String fileName) {
    final titleController = TextEditingController(text: fileName.replaceAll(RegExp(r'\.[^.]+$'), ''));
    String selectedCategory = 'textbook';
    String selectedSubject = _subjects.isNotEmpty
        ? '${_subjects.first['name']} (${_subjects.first['class_name'] ?? 'All Classes'})'
        : 'General';
    String? dialogError;
    String? dialogSuccess;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Configure Upload'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dialogError != null) Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(8), width: double.infinity, decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFF87171))), child: Text(dialogError!, style: const TextStyle(color: Color(0xFF991B1B), fontSize: 13), textAlign: TextAlign.center)),
              if (dialogSuccess != null) Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(8), width: double.infinity, decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFF4ADE80))), child: Text(dialogSuccess!, style: const TextStyle(color: Color(0xFF166534), fontSize: 13), textAlign: TextAlign.center)),
              Text('File: $fileName', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Resource Title'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedCategory,
                decoration: const InputDecoration(labelText: 'Category'),
                items: const [
                  DropdownMenuItem(value: 'textbook', child: Text('Textbook')),
                  DropdownMenuItem(value: 'khan', child: Text('Video')),
                  DropdownMenuItem(value: 'pyq', child: Text('Previous Year Paper (PYQ)')),
                  DropdownMenuItem(value: 'kiwix', child: Text('Kiwix Archive (Library)')),
                  DropdownMenuItem(value: 'notes', child: Text('Notes')),
                ],
                onChanged: (val) => setDialogState(() => selectedCategory = val ?? 'textbook'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedSubject,
                decoration: const InputDecoration(labelText: 'Subject'),
                items: [
                  if (_subjects.isEmpty) const DropdownMenuItem(value: 'General', child: Text('General')),
                  for (final s in _subjects)
                    DropdownMenuItem(
                      value: '${s['name']} (${s['class_name'] ?? 'All Classes'})',
                      child: Text('${s['name']} (${s['class_name'] ?? 'All Classes'})'),
                    ),
                ],
                onChanged: (val) => setDialogState(() => selectedSubject = val ?? 'General'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF13696a)),
              onPressed: () async {
                final title = titleController.text.trim();
                if (title.isEmpty) {
                  setDialogState(() { dialogSuccess = null; dialogError = 'Please enter a title'; });
                  return;
                }
                try {
                  await ApiClient.post('/teacher/import-server-file', queryParameters: {
                    'filename': fileName,
                    'title': title,
                    'type': selectedCategory,
                    'subject': selectedSubject,
                  });
                  _fetchData();
                  setDialogState(() { dialogError = null; dialogSuccess = 'Successfully imported "$title"'; });
                  Future.delayed(const Duration(seconds: 1), () { if (mounted) Navigator.pop(context); });
                } catch (e) {
                  setDialogState(() { dialogSuccess = null; dialogError = 'Error importing file: $e'; });
                }
              },
              child: const Text('Confirm Import'),
            ),
          ],
        ),
      ),
    );
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
                              _showUploadConfigDialog(name);
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  if (_uiNotificationMessage != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: _uiNotificationIsError ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _uiNotificationIsError ? const Color(0xFFF87171) : const Color(0xFF4ADE80)),
                      ),
                      child: Text(
                        _uiNotificationMessage!,
                        style: TextStyle(
                          color: _uiNotificationIsError ? const Color(0xFF991B1B) : const Color(0xFF166534),
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
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
                                ElevatedButton(onPressed: _fetchData, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF13696a)), child: const Text('Refresh Data'))
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
                                _FoldersGrid(
                                  subjects: _subjects,
                                  selectedFilter: _selectedSubjectFilter,
                                  onSelect: (val) => setState(() => _selectedSubjectFilter = val),
                                  onAddSubject: _showAddSubjectDialog,
                                  getIcon: getSymbolIcon,
                                ),
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
                                _FileManifestTable(
                                  resources: _resources,
                                  selectedFilter: _selectedSubjectFilter,
                                ),
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
  final List<Map<String, dynamic>> subjects;
  final String selectedFilter;
  final Function(String) onSelect;
  final VoidCallback onAddSubject;
  final IconData Function(String) getIcon;

  const _FoldersGrid({
    required this.subjects,
    required this.selectedFilter,
    required this.onSelect,
    required this.onAddSubject,
    required this.getIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Subjects / Folders', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF13696a)),
              onPressed: onAddSubject,
              icon: const Icon(Icons.add, size: 18, color: Colors.white),
              label: const Text('Add Subject', style: TextStyle(color: Colors.white)),
            )
          ],
        ),
        const SizedBox(height: 12),
        if (subjects.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(8), color: Colors.white),
            child: const Text('No subjects created yet. Click "Add Subject" to create one.'),
          )
        else
          GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 2.2,
            ),
            shrinkWrap: true,
            itemCount: subjects.length + 1, // +1 for "All Subjects"
            itemBuilder: (context, i) {
              if (i == 0) {
                final isSelected = selectedFilter == 'ALL';
                return InkWell(
                  onTap: () => onSelect('ALL'),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF13696a).withOpacity(0.1) : Colors.white,
                      border: Border.all(color: isSelected ? const Color(0xFF13696a) : Colors.grey.shade200, width: isSelected ? 2 : 1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.apps, color: isSelected ? const Color(0xFF13696a) : Colors.grey.shade600),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('All Subjects', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        )
                      ],
                    ),
                  ),
                );
              }
              final subj = subjects[i - 1];
              final name = subj['name'] ?? 'General';
              final className = subj['class_name'] ?? 'All Classes';
              final displayName = '$name ($className)';
              final symbol = subj['symbol'] ?? 'folder';
              final isSelected = selectedFilter == displayName;

              return InkWell(
                onTap: () => onSelect(displayName),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF13696a).withOpacity(0.1) : Colors.white,
                    border: Border.all(color: isSelected ? const Color(0xFF13696a) : Colors.grey.shade200, width: isSelected ? 2 : 1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(getIcon(symbol), color: isSelected ? const Color(0xFF13696a) : const Color(0xFF13696a)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          displayName,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isSelected ? const Color(0xFF13696a) : Colors.black),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _FileManifestTable extends StatelessWidget {
  final List<Map<String, dynamic>> resources;
  final String selectedFilter;

  const _FileManifestTable({required this.resources, required this.selectedFilter});

  @override
  Widget build(BuildContext context) {
    final filtered = selectedFilter == 'ALL' ? resources : resources.where((r) => r['subject'] == selectedFilter).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(selectedFilter == 'ALL' ? 'Mesh Library (All)' : 'Mesh Library ($selectedFilter)', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('${filtered.length} resources', style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(8), color: Colors.white),
          child: filtered.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Center(child: Text('No resources found in this subject.')),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = filtered[i];
                    final title = r['title'] ?? 'Untitled';
                    final type = r['type'] ?? 'textbook';
                    final subject = r['subject'] ?? 'General';
                    return ListTile(
                      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('Subject: $subject • Type: ${type.toUpperCase()}'),
                      trailing: const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
