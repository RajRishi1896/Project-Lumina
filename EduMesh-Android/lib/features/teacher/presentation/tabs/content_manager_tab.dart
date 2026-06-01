import 'dart:async' as async;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../../../auth/data/auth_service.dart';
import '../../../../core/network/api_client.dart';
import '../../../../shared/services/mock_data_service.dart';
import '../../data/teacher_repository.dart';

class ContentManagerTab extends StatefulWidget {
  const ContentManagerTab({super.key});

  @override
  State<ContentManagerTab> createState() => _ContentManagerTabState();
}

class _ContentManagerTabState extends State<ContentManagerTab> {
  // Upload Resource
  final _titleCtrl = TextEditingController();
  final _uploadSubjectCtrl = TextEditingController();
  final _fileUrlCtrl = TextEditingController();
  String _selectedType = 'textbook';

  // Add Subject
  final _subjNameCtrl = TextEditingController();
  final _subjSymbolCtrl = TextEditingController();
  final _subjClassCtrl = TextEditingController(text: 'All Classes');

  // Mesh Library filters
  final _searchCtrl = TextEditingController();
  String _filterSubject = 'All';

  // Import Server File
  final _importTitleCtrl = TextEditingController();
  final _importSubjectCtrl = TextEditingController();
  String _importType = 'textbook';

  // ZIM URL
  final _zimUrlCtrl = TextEditingController();

  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _resources = [];
  List<Map<String, dynamic>> _serverFiles = [];
  bool _loading = true;
  String? _error;
  int? _zimUploadMaxSize;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _uploadSubjectCtrl.dispose();
    _fileUrlCtrl.dispose();
    _subjNameCtrl.dispose();
    _subjSymbolCtrl.dispose();
    _subjClassCtrl.dispose();
    _searchCtrl.dispose();
    _importTitleCtrl.dispose();
    _importSubjectCtrl.dispose();
    _zimUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final subjects = await TeacherRepository.getSubjects();
      final resources = await TeacherRepository.getResources();
      final limits = await TeacherRepository.getLimits();
      if (mounted) {
        setState(() {
          _subjects = subjects;
          _resources = resources;
          _zimUploadMaxSize = limits['zim_upload_max_size'];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<String> _downloadToTemp(String url) async {
    final response = await ApiClient.dio.get(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final dir = await getTemporaryDirectory();
    final name = url.split('/').last.split('?').first;
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(response.data);
    return file.path;
  }

  Future<void> _uploadResource() async {
    final title = _titleCtrl.text.trim();
    final url = _fileUrlCtrl.text.trim();
    if (title.isEmpty || url.isEmpty) return;
    setState(() => _uploading = true);
    try {
      final filePath = await _downloadToTemp(url);
      final fileName = url.split('/').last.split('?').first;
      await TeacherRepository.uploadResource(
        title: title,
        type: _selectedType,
        subject: _uploadSubjectCtrl.text.trim().isEmpty ? 'General' : _uploadSubjectCtrl.text.trim(),
        filePath: filePath,
        fileName: fileName,
      );
      async.unawaited(File(filePath).delete());
      if (mounted) {
        _titleCtrl.clear();
        _fileUrlCtrl.clear();
        _uploadSubjectCtrl.clear();
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Resource uploaded successfully')));
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _uploadZim() async {
    final url = _zimUrlCtrl.text.trim();
    if (url.isEmpty) return;
    if (_zimUploadMaxSize != null) {
      try {
        final headResp = await ApiClient.dio.head(url);
        final size = int.tryParse(headResp.headers.value('content-length') ?? '0') ?? 0;
        if (size > _zimUploadMaxSize!) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                    'File exceeds maximum ZIM upload size of ${_zimUploadMaxSize! ~/ (1024 * 1024)} MiB')));
          }
          return;
        }
      } catch (_) {}
    }
    setState(() => _uploading = true);
    try {
      final filePath = await _downloadToTemp(url);
      final fileName = url.split('/').last.split('?').first;
      final resp = await TeacherRepository.uploadZim(filePath, fileName);
      async.unawaited(File(filePath).delete());
      if (mounted) {
        final imported = (resp['imported'] as List?)?.length ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('ZIM uploaded: $imported pages imported')));
        _zimUrlCtrl.clear();
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ZIM upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _addSubject() async {
    final name = _subjNameCtrl.text.trim();
    final symbol = _subjSymbolCtrl.text.trim();
    final className = _subjClassCtrl.text.trim();
    if (name.isEmpty || symbol.isEmpty) return;
    try {
      await TeacherRepository.createSubject(name, symbol, className);
      if (mounted) {
        _subjNameCtrl.clear();
        _subjSymbolCtrl.clear();
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Subject added')));
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _deleteSubject(String name) async {
    final otherSubjects =
        _subjects.where((s) => s['name'] != name).map((s) => s['name'] as String).toList();
    String? transferTo;
    if (otherSubjects.isNotEmpty) {
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text('Delete "$name"?'),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text('Transfer resources to another subject, or delete all.'),
            ),
            ...otherSubjects.map((s) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, s),
                  child: Text('Transfer to $s'),
                )),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('Delete all resources', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      );
      if (result == null) return;
      transferTo = result.isEmpty ? null : result;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Delete "$name"?'),
          content: const Text('All resources in this subject will be deleted.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      await TeacherRepository.deleteSubject(name, transferTo: transferTo);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Subject deleted')));
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _deleteResource(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Resource?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await TeacherRepository.deleteResource(id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Resource deleted')));
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _loadServerFiles() async {
    try {
      final files = await TeacherRepository.getServerFiles();
      if (mounted) setState(() => _serverFiles = files);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to load server files: $e')));
      }
    }
  }

  Future<void> _importServerFile(String filename) async {
    final formKey = GlobalKey<FormState>();
    _importTitleCtrl.text = filename;
    _importType = 'textbook';

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import Server File'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _importTitleCtrl,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              DropdownButtonFormField<String>(
                initialValue: _importType,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: 'textbook', child: Text('Textbook')),
                  DropdownMenuItem(value: 'video', child: Text('Video')),
                  DropdownMenuItem(value: 'pyq', child: Text('PYQ')),
                  DropdownMenuItem(value: 'kiwix', child: Text('Kiwix')),
                  DropdownMenuItem(value: 'notes', child: Text('Notes')),
                ],
                onChanged: (v) => _importType = v ?? 'textbook',
              ),
              TextFormField(
                controller: _importSubjectCtrl,
                decoration: const InputDecoration(labelText: 'Subject'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              try {
                await TeacherRepository.importServerFile(
                  filename: filename,
                  title: _importTitleCtrl.text.trim(),
                  type: _importType,
                  subject: _importSubjectCtrl.text.trim().isEmpty
                      ? 'General'
                      : _importSubjectCtrl.text.trim(),
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('File imported')));
                  _loadData();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Import failed: $e')));
                }
              }
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredResources {
    var list = _resources;
    if (_filterSubject != 'All') {
      list = list.where((r) => r['subject'] == _filterSubject).toList();
    }
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list.where((r) =>
          (r['title']?.toString().toLowerCase() ?? '').contains(query)).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Error: $_error', style: TextStyle(color: cs.error)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (AuthService.isDemoMode) _buildDemoActions(cs),
          SizedBox(height: 16.h),
          _buildUploadSection(cs),
          SizedBox(height: 24.h),
          _buildAddSubjectSection(cs),
          SizedBox(height: 24.h),
          _buildSubjectsTable(cs),
          SizedBox(height: 24.h),
          _buildMeshLibrary(cs),
          SizedBox(height: 24.h),
          _buildZimSection(cs),
          SizedBox(height: 24.h),
          _buildServerImportSection(cs),
        ],
      ),
    );
  }

  Widget _buildUploadSection(ColorScheme cs) {
    return Card(
      color: cs.surfaceContainer,
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Upload Resource',
                style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700, color: cs.onSurface)),
            SizedBox(height: 16.h),
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
            ),
            SizedBox(height: 12.h),
            DropdownButtonFormField<String>(
              initialValue: _selectedType,
              decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'textbook', child: Text('Textbook')),
                DropdownMenuItem(value: 'video', child: Text('Video')),
                DropdownMenuItem(value: 'pyq', child: Text('PYQ')),
                DropdownMenuItem(value: 'kiwix', child: Text('Kiwix')),
                DropdownMenuItem(value: 'notes', child: Text('Notes')),
              ],
              onChanged: (v) => setState(() => _selectedType = v ?? 'textbook'),
            ),
            SizedBox(height: 12.h),
            TextFormField(
              controller: _uploadSubjectCtrl,
              decoration: const InputDecoration(labelText: 'Subject', border: OutlineInputBorder()),
            ),
            SizedBox(height: 12.h),
            TextFormField(
              controller: _fileUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'File URL',
                hintText: 'https://example.com/file.pdf',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 12.h),
            ElevatedButton(
              onPressed: (_titleCtrl.text.trim().isNotEmpty && _fileUrlCtrl.text.trim().isNotEmpty && !_uploading)
                  ? _uploadResource
                  : null,
              child: _uploading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Download & Upload'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddSubjectSection(ColorScheme cs) {
    return Card(
      color: cs.surfaceContainer,
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add Subject',
                style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700, color: cs.onSurface)),
            SizedBox(height: 16.h),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _subjNameCtrl,
                    decoration: const InputDecoration(labelText: 'Subject Name', border: OutlineInputBorder()),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: TextFormField(
                    controller: _subjSymbolCtrl,
                    decoration: const InputDecoration(labelText: 'Icon Symbol', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            TextFormField(
              controller: _subjClassCtrl,
              decoration: const InputDecoration(labelText: 'Class / Grade', border: OutlineInputBorder()),
            ),
            SizedBox(height: 12.h),
            ElevatedButton(onPressed: _addSubject, child: const Text('Add Subject')),
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectsTable(ColorScheme cs) {
    return Card(
      color: cs.surfaceContainer,
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Manage Subjects',
                style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700, color: cs.onSurface)),
            SizedBox(height: 12.h),
            if (_subjects.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 24.h),
                child: Center(child: Text('No subjects yet', style: TextStyle(color: cs.onSurfaceVariant))),
              )
            else
              ...List.generate(_subjects.length, (i) {
                final subj = _subjects[i];
                return ListTile(
                  leading: Icon(Icons.book, color: cs.primary),
                  title: Text(subj['name'] ?? ''),
                  subtitle: Text('${subj['symbol'] ?? ''}  -  ${subj['class_name'] ?? 'All Classes'}'),
                  trailing: IconButton(
                    icon: Icon(Icons.delete_outline, color: cs.error),
                    onPressed: () => _deleteSubject(subj['name'] ?? ''),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildMeshLibrary(ColorScheme cs) {
    return Card(
      color: cs.surfaceContainer,
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mesh Library',
                style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700, color: cs.onSurface)),
            SizedBox(height: 12.h),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Search resources...',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                SizedBox(width: 12.w),
                DropdownButton<String>(
                  value: _filterSubject,
                  items: [
                    const DropdownMenuItem(value: 'All', child: Text('All Subjects')),
                    ..._subjects.map((s) => DropdownMenuItem(
                          value: s['name'] as String,
                          child: Text(s['name'] as String),
                        )),
                  ],
                  onChanged: (v) => setState(() => _filterSubject = v ?? 'All'),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            if (_filteredResources.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 24.h),
                child: Center(
                    child: Text('No resources found',
                        style: TextStyle(color: cs.onSurfaceVariant))),
              )
            else
              ...List.generate(_filteredResources.length, (i) {
                final r = _filteredResources[i];
                final type = r['type'] ?? '';
                final icon = type == 'video'
                    ? Icons.video_library
                    : type == 'kiwix'
                        ? Icons.language
                        : type == 'pyq'
                            ? Icons.quiz
                            : Icons.description;
                return ListTile(
                  leading: Icon(icon, color: cs.primary),
                  title: Text(r['title'] ?? 'Untitled'),
                  subtitle: Text('${r['subject'] ?? 'General'}  -  $type'),
                  trailing: IconButton(
                    icon: Icon(Icons.delete_outline, color: cs.error),
                    onPressed: () => _deleteResource(r['id'] is int ? r['id'] : int.tryParse(r['id']?.toString() ?? '') ?? 0),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildZimSection(ColorScheme cs) {
    final maxSizeMiB = _zimUploadMaxSize != null
        ? '${_zimUploadMaxSize! ~/ (1024 * 1024)} MiB max'
        : 'Size limit unknown';
    return Card(
      color: cs.surfaceContainer,
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Upload ZIM Archive',
                style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700, color: cs.onSurface)),
            SizedBox(height: 8.h),
            Text('$maxSizeMiB — provide a direct download URL to a ZIM/ZIP archive.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.sp)),
            SizedBox(height: 12.h),
            TextFormField(
              controller: _zimUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'ZIM File URL',
                hintText: 'https://example.com/content.zim.zip',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 12.h),
            ElevatedButton(
              onPressed: (_zimUrlCtrl.text.trim().isNotEmpty && !_uploading) ? _uploadZim : null,
              child: _uploading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Download & Import ZIM'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerImportSection(ColorScheme cs) {
    return Card(
      color: cs.surfaceContainer,
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Import from Server',
                style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700, color: cs.onSurface)),
            SizedBox(height: 12.h),
            ElevatedButton.icon(
              onPressed: () async {
                await _loadServerFiles();
                if (mounted && _serverFiles.isNotEmpty) {
                  _showServerFilesDialog(cs);
                }
              },
              icon: const Icon(Icons.cloud_download),
              label: const Text('Browse Server Files'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDemoActions(ColorScheme cs) {
    return Card(
      color: cs.primary.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: cs.primary.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.science_rounded, size: 18.sp, color: cs.primary),
                SizedBox(width: 8.w),
                Text('Demo Actions',
                    style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w700,
                        color: cs.primary)),
              ],
            ),
            SizedBox(height: 12.h),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _subjects = MockDataService.getSampleSubjects();
                        _resources = MockDataService.getSampleResources();
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Sample subjects & resources loaded')),
                      );
                    },
                    icon: const Icon(Icons.playlist_add, size: 18),
                    label: const Text('Load Sample Data'),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _subjects = [];
                        _resources = [];
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Demo data cleared')),
                      );
                    },
                    icon: const Icon(Icons.clear_all, size: 18),
                    label: const Text('Clear'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showServerFilesDialog(ColorScheme cs) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server Files'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _serverFiles.length,
            itemBuilder: (ctx, i) {
              final f = _serverFiles[i];
              final name = f['name'] ?? 'unknown';
              final size = f['size'] ?? 0;
              return ListTile(
                title: Text(name),
                subtitle: Text('${(size / 1024).toStringAsFixed(1)} KB'),
                trailing: TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _importServerFile(name);
                  },
                  child: const Text('Import'),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }
}
