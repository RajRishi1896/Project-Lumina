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
          if (diff.inHours < 1) {
            _lastSyncStr = 'Just now';
          } else {
            _lastSyncStr = '${diff.inHours}h ago';
          }
        }
      });
    }
  }

  Future<void> _checkConnection() async {
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
          if (entity is File) {
            appDataSize += await entity.length();
          }
        }
      }
      final apkSize = await AuthService().getApkSize();
      final totalUsedBytes = appDataSize + apkSize;
      
      final storageInfo = await _storageService.getStorageInfo();
      final totalBytes = storageInfo['totalBytes'] ?? (128 * 1024 * 1024 * 1024);
      
      if (mounted) {
        setState(() {
          final usedMb = totalUsedBytes / (1024 * 1024);
          if (usedMb < 1024) {
            _totalStorageUsedStr = '${usedMb.toStringAsFixed(1)} MB used';
          } else {
            _totalStorageUsedStr = '${(usedMb / 1024).toStringAsFixed(1)} GB used';
          }
          
          final totalGb = totalBytes / (1024 * 1024 * 1024);
          _totalCapacityStr = '${totalGb.toStringAsFixed(0)} GB Total';
          
          _totalStorageProgress = (totalUsedBytes / totalBytes).clamp(0.0, 1.0);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _totalStorageUsedStr = 'Unknown');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_isConnected && !widget.forceOffline) {
      return widget.child;
    }

    return _ErrorStateScreen(
      isConnected: _isConnected,
      lastSync: _lastSyncStr,
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => LuminaSettingsSheet(
        onManageStorage: () => _showOfflineStorage(context),
      ),
    );
  }

  void _showOfflineStorage(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.storage, size: 20.sp, color: Theme.of(context).colorScheme.primary),
                  SizedBox(width: 8.w),
                  Text(
                    'Offline Storage',
                    style: TextStyle(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_totalStorageUsedStr,
                      style: TextStyle(fontSize: 12.sp, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  Text(_totalCapacityStr,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: LuminaColors.academicTeal)),
                ],
              ),
              SizedBox(height: 8.h),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _totalStorageProgress,
                  minHeight: 16.h,
                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  valueColor: const AlwaysStoppedAnimation<Color>(LuminaColors.academicTeal),
                ),
              ),
              SizedBox(height: 24.h),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: LuminaColors.academicTeal),
                    foregroundColor: LuminaColors.academicTeal,
                    minimumSize: const Size(48, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: const Text('Close'),
                ),
              ),
              SizedBox(height: 8.h),
            ],
          ),
        ),
      ),
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
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        title: Text(
          'EduPortal Offline',
          style: GoogleFonts.atkinsonHyperlegible(
            fontWeight: FontWeight.bold,
            color: cs.primary,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.settings, color: cs.primary),
            onPressed: onOpenSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(24.w),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: 40.h),
                Center(
                  child: Container(
                    width: 200.w,
                    height: 200.w,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh,
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Icon(
                      isEmptyLibrary ? Icons.library_books : Icons.cloud_off,
                      size: 100.sp,
                      color: cs.primary.withOpacity(0.2),
                    ),
                  ),
                ),
                SizedBox(height: 32.h),
                Text(
                  isEmptyLibrary 
                      ? "Your library is empty." 
                      : "You've lost connection to the Hub.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.atkinsonHyperlegible(
                    fontSize: 28.sp,
                    fontWeight: FontWeight.w800,
                    color: cs.primary,
                    height: 1.2,
                  ),
                ),
                SizedBox(height: 12.h),
                Text(
                  isEmptyLibrary
                      ? "Connect to the Hub to download educational resources."
                      : "Please check your Wi-Fi settings. Some features may be unavailable until you are back online.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.atkinsonHyperlegible(
                    fontSize: 16.sp,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: 40.h),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reconnect'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.secondary,
                          foregroundColor: cs.onSecondary,
                          minimumSize: Size(0, 56.h),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12.h),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onOpenWifi,
                        icon: const Icon(Icons.wifi),
                        label: const Text('Open Wi-Fi Settings'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: cs.secondary,
                          side: BorderSide(color: cs.secondary, width: 2),
                          minimumSize: Size(0, 56.h),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 40.h),
                _buildBentoStatus(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBentoStatus(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12.h,
      crossAxisSpacing: 12.w,
      childAspectRatio: 1.5,
      children: [
        _BentoCard(
          icon: isConnected ? Icons.wifi : Icons.wifi_off,
          label: 'Local Network',
          value: isConnected ? 'Connected' : 'Disconnected',
          color: isConnected ? LuminaColors.academicTeal : const Color(0xFFCB9524),
          cs: cs,
        ),
        _BentoCard(
          icon: Icons.sync,
          label: 'Sync Status',
          value: lastSync,
          color: cs.secondary,
          cs: cs,
        ),
      ],
    );
  }
}

class _BentoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final ColorScheme cs;

  const _BentoCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 16.sp, color: color),
              SizedBox(width: 4.w),
              Text(
                label.toUpperCase(),
                style: GoogleFonts.atkinsonHyperlegible(
                  fontSize: 10.sp,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          Text(
            value,
            style: GoogleFonts.atkinsonHyperlegible(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: cs.primary,
            ),
          ),
        ],
      ),
    );
  }
}
