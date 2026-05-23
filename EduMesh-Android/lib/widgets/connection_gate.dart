import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:app_settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/services/connection_service.dart';
import '../core/services/storage_service.dart';
import '../core/constants/lumina_colors.dart';
import '../shared/widgets/lumina_settings_sheet.dart';
import '../features/auth/data/auth_service.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class ConnectionGate extends StatefulWidget {
  final Widget child;
  final bool forceOffline;

  const ConnectionGate({
    super.key,
    required this.child,
    this.forceOffline = false,
  });

  @override
  State<ConnectionGate> createState() => _ConnectionGateState();
}

class _ConnectionGateState extends State<ConnectionGate> {
  bool _isConnected = true;
  bool _isChecking = true;
  final ConnectionService _connectionService = ConnectionService();
  final StorageService _storageService = StorageService();

  String _totalStorageUsedStr = 'Calculating...';
  String _totalCapacityStr = 'Calculating...';
  double _totalStorageProgress = 0.0;
  String _lastSyncStr = 'Never';

  @override
  void initState() {
    super.initState();
    _fetchStats();
    if (widget.forceOffline) {
      _isConnected = false;
      _isChecking = false;
    } else {
      _checkConnection();
    }
  }

  Future<void> _fetchStats() async {
    await _calcTotalStorage();
    await _fetchSyncStatus();
  }

  Future<void> _fetchSyncStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSyncTs = prefs.getInt('last_sync_timestamp');
    if (mounted) {
      setState(() {
        if (lastSyncTs == null) {
          _lastSyncStr = 'Never';
        } else {
          final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastSyncTs));
          _lastSyncStr = diff.inHours < 1 ? 'Just now' : '${diff.inHours}h ago';
        }
      });
    }
  }

  Future<void> _checkConnection() async {
    if (!mounted) return;
    setState(() => _isChecking = true);
    final connected = await _connectionService.ping(timeout: const Duration(seconds: 5));
    if (mounted) {
      setState(() {
        _isConnected = connected;
        _isChecking = false;
      });
    }
  }

  Future<void> _calcTotalStorage() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      int appDataSize = 0;
      if (await dir.exists()) {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) appDataSize += await entity.length();
        }
      }
      final apkSize = await AuthService().getApkSize();
      final totalUsedBytes = (appDataSize + apkSize).toDouble();
      final Map<String, dynamic>? storageInfo = await _storageService.getStorageInfo();
      final dynamic rawBytes = storageInfo?['totalBytes'];
      final double totalBytes = (rawBytes != null) ? (rawBytes as num).toDouble() : 134217728000.0;

      if (mounted) {
        setState(() {
          final usedMb = totalUsedBytes / 1048576;
          _totalStorageUsedStr = usedMb < 1024 ? '${usedMb.toStringAsFixed(1)} MB used' : '${(usedMb / 1024).toStringAsFixed(1)} GB used';
          _totalCapacityStr = '${(totalBytes / 1073741824).toStringAsFixed(0)} GB Total';
          _totalStorageProgress = (totalUsedBytes / totalBytes).clamp(0.0, 1.0);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _totalStorageUsedStr = 'Unknown');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    
    // Check for null or empty strings before passing to widget
    if (_isConnected && !widget.forceOffline) return widget.child;

    return _ErrorStateScreen(
      isConnected: _isConnected,
      lastSync: _lastSyncStr.isEmpty ? 'Never' : _lastSyncStr, 
      onRetry: _checkConnection,
      onOpenSettings: () => _showSettings(context),
      onOpenWifi: () => AppSettings.openAppSettings(type: AppSettingsType.wifi),
      isEmptyLibrary: widget.forceOffline,
    );
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => LuminaSettingsSheet(onManageStorage: () => Navigator.pop(context)),
    );
  }
}

class _ErrorStateScreen extends StatelessWidget {
  final bool isConnected;
  final String lastSync;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenWifi;
  final bool isEmptyLibrary;

  const _ErrorStateScreen({
    required this.isConnected,
    required this.lastSync,
    required this.onRetry,
    required this.onOpenSettings,
    required this.onOpenWifi,
    this.isEmptyLibrary = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: Text("Offline Mode\nLast Sync: $lastSync", textAlign: TextAlign.center)),
    );
  }
}