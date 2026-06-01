import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'login_page.dart';
import '../../../core/services/connection_service.dart';
import '../../../shared/widgets/lumina_stepper.dart';
import '../data/auth_service.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  String _hubStrength = 'Checking...';
  String _storageUsed = 'Calculating...';
  final ConnectionService _connectionService = ConnectionService();

  @override
  void initState() {
    super.initState();
    _fetchSystemStatus();
  }

  Future<void> _fetchSystemStatus() async {
    // 1. Check Hub Strength (via latency)
    final stopwatch = Stopwatch()..start();
    final isConnected = await _connectionService.ping(timeout: const Duration(seconds: 2));
    stopwatch.stop();
    
    if (mounted) {
      setState(() {
        if (!isConnected) {
          _hubStrength = 'Offline';
        } else {
          final ms = stopwatch.elapsedMilliseconds;
          if (ms < 50) {
            _hubStrength = 'Excellent';
          } else if (ms < 150) {
            _hubStrength = 'Good';
          } else {
            _hubStrength = 'Fair';
          }
        }
      });
    }

    // 2. Calculate Local Storage Used (including APK)
    try {
      final dir = await getApplicationDocumentsDirectory();
      final sizeInBytes = await _getDirSize(dir);
      final apkSize = await AuthService().getApkSize();
      final totalSizeInMb = (sizeInBytes + apkSize) / (1024 * 1024);
      
      if (mounted) {
        setState(() {
          if (totalSizeInMb < 1024) {
            _storageUsed = '${totalSizeInMb.toStringAsFixed(1)} MB Used';
          } else {
            _storageUsed = '${(totalSizeInMb / 1024).toStringAsFixed(1)} GB Used';
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _storageUsed = 'Unknown');
    }
  }

  Future<int> _getDirSize(Directory dir) async {
    int totalSize = 0;
    try {
      if (await dir.exists()) {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            totalSize += await entity.length();
          }
        }
      }
    } catch (e) {
      // Ignore directory errors
    }
    return totalSize;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 24.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                LuminaStepper(currentStep: 0),
                SizedBox(height: 32.h),
                _buildIllustration(context),
                SizedBox(height: 40.h),
                _buildContent(context),
                SizedBox(height: 32.h),
                _buildLanguageSelection(context),
                SizedBox(height: 48.h),
                _buildCTA(context),
                SizedBox(height: 40.h),
                _buildDeviceStatus(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Stepper logic moved to LuminaStepper

  Widget _buildIllustration(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: 312.w,
      height: 312.w,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: EdgeInsets.all(24.w),
      child: Stack(
        children: [
          Center(
            child: SvgPicture.string(
              '''
              <svg viewBox="0 0 240 180" xmlns="http://www.w3.org/2000/svg">
                <rect x="40" y="80" width="100" height="60" rx="4" fill="none" stroke="#002045" stroke-width="3"/>
                <rect x="30" y="140" width="120" height="8" rx="2" fill="#002045"/>
                <rect x="160" y="40" width="45" height="85" rx="6" fill="none" stroke="#13696a" stroke-width="3"/>
                <rect x="175" y="48" width="15" height="4" rx="2" fill="#13696a"/>
                <path d="M140 70 Q155 55 170 70" fill="none" stroke="#f8bc4b" stroke-linecap="round" stroke-width="3"/>
                <path d="M140 50 Q160 30 180 50" fill="none" stroke="#f8bc4b" stroke-dasharray="4 4" stroke-linecap="round" stroke-width="3"/>
                <circle cx="155" cy="100" r="4" fill="#89d3d4"/>
                <circle cx="165" cy="115" r="4" fill="#89d3d4"/>
              </svg>
              ''',
              width: 240.w,
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sync, color: cs.secondary, size: 18.sp),
                    SizedBox(width: 8.w),
                    Text(
                      'No Internet Connection Required!',
                      style: GoogleFonts.atkinsonHyperlegible(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        Text(
          'Connected to Learning Hub',
          textAlign: TextAlign.center,
          style: GoogleFonts.atkinsonHyperlegible(
            fontSize: 32.sp,
            fontWeight: FontWeight.w800,
            color: cs.primary,
            height: 1.1,
          ),
        ),
        SizedBox(height: 12.h),
        Text(
          'No Internet Needed. Access thousands of books and courses locally.',
          textAlign: TextAlign.center,
          style: GoogleFonts.atkinsonHyperlegible(
            fontSize: 16.sp,
            fontWeight: FontWeight.w400,
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildLanguageSelection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SELECT LANGUAGE',
          style: GoogleFonts.atkinsonHyperlegible(
            fontSize: 12.sp,
            fontWeight: FontWeight.w700,
            color: cs.secondary,
            letterSpacing: 1.5,
          ),
        ),
        SizedBox(height: 12.h),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12.h,
          crossAxisSpacing: 12.w,
          childAspectRatio: 2.5,
          children: [
            _LanguageButton(label: 'English', isSelected: true, isEnabled: true, cs: cs),
            _LanguageButton(label: 'Kiswahili', isSelected: false, isEnabled: false, cs: cs),
            _LanguageButton(label: 'Hindi', isSelected: false, isEnabled: false, cs: cs),
            _LanguageButton(label: 'More...', isSelected: false, isEnabled: false, cs: cs),
          ],
        ),
      ],
    );
  }

  Widget _buildCTA(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LoginPage()),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFF8BC4B),
          foregroundColor: const Color(0xFF271900),
          padding: EdgeInsets.symmetric(vertical: 16.h),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.r),
            side: const BorderSide(color: Color(0xFF5F4100), width: 2),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Enter Portal',
              style: GoogleFonts.atkinsonHyperlegible(
                fontSize: 20.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(width: 8.w),
            Icon(Icons.arrow_forward, size: 24.sp),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceStatus(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.only(top: 24.h),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatusItem(
            icon: Icons.wifi,
            label: 'Hub Strength',
            value: _hubStrength,
            cs: cs,
          ),
          _StatusItem(
            icon: Icons.storage,
            label: 'Local Storage',
            value: _storageUsed,
            cs: cs,
          ),
        ],
      ),
    );
  }
}

class _LanguageButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isEnabled;
  final ColorScheme cs;

  const _LanguageButton({
    required this.label,
    required this.isSelected,
    required this.isEnabled,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isEnabled ? Colors.white : cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(
          color: isSelected 
              ? cs.primary 
              : (isEnabled ? cs.outlineVariant : cs.outlineVariant.withValues(alpha: 0.5)),
          width: isSelected ? 2 : 1,
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.atkinsonHyperlegible(
              fontSize: 14.sp,
              fontWeight: FontWeight.bold,
              color: isSelected 
                  ? cs.primary 
                  : (isEnabled ? cs.onSurfaceVariant : cs.onSurfaceVariant.withValues(alpha: 0.4)),
            ),
          ),
          if (isSelected)
            Icon(Icons.check_circle, color: cs.primary, size: 18.sp),
        ],
      ),
    );
  }
}

class _StatusItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ColorScheme cs;

  const _StatusItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: cs.secondary, size: 24.sp),
        SizedBox(width: 8.w),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.atkinsonHyperlegible(
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            Text(
              value.toUpperCase(),
              style: GoogleFonts.atkinsonHyperlegible(
                fontSize: 10.sp,
                fontWeight: FontWeight.w800,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
