import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../data/teacher_repository.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  String _retentionPolicy = '30d';
  bool _loadingSettings = true;
  bool _savingRetention = false;

  List<String> _auditLog = [];
  bool _loadingLog = true;
  final _logSearchCtrl = TextEditingController();
  String _logSearch = '';

  String _downloadDuration = 'all';
  bool _downloadingLogs = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadAuditLog();
  }

  @override
  void dispose() {
    _logSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _loadingSettings = true);
    try {
      final settings = await TeacherRepository.getAdminSettings();
      if (mounted) {
        setState(() {
          _retentionPolicy = settings['log_retention'] ?? '30d';
          _loadingSettings = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingSettings = false);
    }
  }

  Future<void> _saveRetention() async {
    setState(() => _savingRetention = true);
    try {
      await TeacherRepository.setLogRetention(_retentionPolicy);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Log retention policy updated')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _savingRetention = false);
    }
  }

  Future<void> _loadAuditLog() async {
    setState(() => _loadingLog = true);
    try {
      final log = await TeacherRepository.getAdminLog(limit: 50);
      if (mounted) setState(() { _auditLog = log; _loadingLog = false; });
    } catch (e) {
      if (mounted) setState(() => _loadingLog = false);
    }
  }

  Future<void> _downloadLogs() async {
    setState(() => _downloadingLogs = true);
    try {
      final content = await TeacherRepository.downloadAdminLogs(duration: _downloadDuration);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Logs downloaded (${content.length} characters)'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _downloadingLogs = false);
    }
  }

  String _retentionLabel(String val) {
    switch (val) {
      case '24h': return '24 Hours';
      case '7d': return '7 Days';
      case '30d': return '30 Days';
      case '3m': return '3 Months';
      case '6m': return '6 Months';
      case 'never': return 'Keep Forever';
      case 'none': return 'No Logging';
      default: return val;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRetentionCard(cs),
          SizedBox(height: 24.h),
          _buildAuditLogCard(cs),
          SizedBox(height: 24.h),
          _buildDownloadCard(cs),
        ],
      ),
    );
  }

  Widget _buildRetentionCard(ColorScheme cs) {
    return Card(
      color: cs.surfaceContainer,
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Log Retention Policy',
                style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700, color: cs.onSurface)),
            SizedBox(height: 12.h),
            if (_loadingSettings)
              const LinearProgressIndicator()
            else
              DropdownButtonFormField<String>(
                value: _retentionPolicy,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: ['24h', '7d', '30d', '3m', '6m', 'never', 'none']
                    .map((v) => DropdownMenuItem(value: v, child: Text(_retentionLabel(v))))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _retentionPolicy = v);
                },
              ),
            SizedBox(height: 12.h),
            ElevatedButton(
              onPressed: _savingRetention ? null : _saveRetention,
              child: _savingRetention
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save Policy'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuditLogCard(ColorScheme cs) {
    final filtered = _logSearch.isEmpty
        ? _auditLog
        : _auditLog.where((l) => l.toLowerCase().contains(_logSearch.toLowerCase())).toList();

    return Card(
      color: cs.surfaceContainer,
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Admin Audit Log',
                    style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700, color: cs.onSurface)),
                IconButton(
                  icon: Icon(Icons.refresh, color: cs.primary),
                  onPressed: _loadAuditLog,
                  tooltip: 'Refresh',
                ),
              ],
            ),
            SizedBox(height: 12.h),
            TextFormField(
              controller: _logSearchCtrl,
              decoration: const InputDecoration(
                labelText: 'Search logs...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _logSearch = v),
            ),
            SizedBox(height: 12.h),
            if (_loadingLog)
              const Center(child: CircularProgressIndicator())
            else if (filtered.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 24.h),
                child: Center(child: Text('No log entries found', style: TextStyle(color: cs.onSurfaceVariant))),
              )
            else
              SizedBox(
                height: 300.h,
                child: ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: 6.h),
                      child: Text(filtered[i], style: TextStyle(fontSize: 11.sp, fontFamily: 'monospace')),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadCard(ColorScheme cs) {
    return Card(
      color: cs.surfaceContainer,
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Download Audit Logs',
                style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700, color: cs.onSurface)),
            SizedBox(height: 12.h),
            DropdownButtonFormField<String>(
              value: _downloadDuration,
              decoration: const InputDecoration(labelText: 'Duration', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(value: 'all', child: Text('All Time')),
                const DropdownMenuItem(value: '24h', child: Text('Last 24 Hours')),
                const DropdownMenuItem(value: '7d', child: Text('Last 7 Days')),
                const DropdownMenuItem(value: '30d', child: Text('Last 30 Days')),
                const DropdownMenuItem(value: '3m', child: Text('Last 3 Months')),
                const DropdownMenuItem(value: '6m', child: Text('Last 6 Months')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _downloadDuration = v);
              },
            ),
            SizedBox(height: 12.h),
            ElevatedButton.icon(
              onPressed: _downloadingLogs ? null : _downloadLogs,
              icon: _downloadingLogs
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download),
              label: const Text('Download'),
            ),
          ],
        ),
      ),
    );
  }
}
