import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';
import 'login_page.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/lumina_colors.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/services/connection_service.dart';
import '../../../core/services/app_info_service.dart';
import '../../../shared/widgets/lumina_stepper.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';

const _illustrationSvg = '''
<svg width="1677" height="1100" viewBox="0 0 1677 1100" fill="none" xmlns="http://www.w3.org/2000/svg">
<rect width="1676.46" height="1100" fill="white"/>
<rect x="549.328" y="562" width="580" height="380" rx="30" stroke="#1F2933" stroke-width="20"/>
<rect width="661" height="48" rx="12" transform="matrix(1 0 0 -1 508.328 1000)" fill="#1F2933"/>
<rect x="191.827" y="593.788" width="207" height="107.18" rx="11" transform="rotate(79.1944 191.827 593.788)" stroke="#007083" stroke-width="10"/>
<path d="M132.551 629.835L154.932 625.564" stroke="#007083" stroke-width="10" stroke-linecap="round"/>
<rect x="572.799" y="180.77" width="203" height="122.582" rx="7" transform="rotate(95.7559 572.799 180.77)" stroke="#007083" stroke-width="10"/>
<rect x="1574.41" y="653.01" width="212" height="129.255" rx="7" transform="rotate(92.9959 1574.41 653.01)" stroke="#007083" stroke-width="10"/>
<path d="M1514.73 833.5L1541.6 834.907" stroke="#007083" stroke-width="10" stroke-linecap="round"/>
<rect x="1360.78" y="127.629" width="203" height="247.411" rx="7" transform="rotate(82.2411 1360.78 127.629)" stroke="#007083" stroke-width="10"/>
<path d="M1146.62 179.612L1172.25 176.12" stroke="#007083" stroke-width="10" stroke-linecap="round"/>
<path d="M804.239 461.501C808.781 456.63 814.273 452.742 820.375 450.075C826.478 447.409 833.067 446.024 839.727 446.001C846.386 445.977 852.98 447.319 859.101 449.942C865.222 452.566 870.743 456.415 875.319 461.254M782.854 431.803C790.121 424.009 798.907 417.789 808.672 413.522C818.436 409.256 828.97 407.037 839.625 407C850.281 406.963 860.826 409.111 870.62 413.308C880.414 417.506 889.248 423.666 896.571 431.409M839.897 504.501C834.512 504.501 830.147 500.135 830.147 494.751C830.147 489.366 834.512 485.001 839.897 485.001C845.282 485.001 849.647 489.366 849.647 494.751C849.647 500.135 845.282 504.501 839.897 504.501Z" stroke="#F5A623" stroke-width="12" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M754.328 405.209C765.229 393.519 778.409 384.187 793.056 377.788C807.702 371.389 823.497 368.056 839.48 368C855.465 367.944 871.301 371.166 885.992 377.462C900.683 383.759 913.93 393.004 924.913 404.617" stroke="#F5A623" stroke-width="12" stroke-linecap="round" stroke-linejoin="round" stroke-dasharray="24 24"/>
<path d="M430.829 740.672C425.958 736.13 422.07 730.638 419.403 724.535C416.738 718.433 415.352 711.843 415.329 705.183C415.305 698.524 416.647 691.93 419.271 685.809C421.895 679.688 425.744 674.168 430.583 669.592M401.131 762.057C393.338 754.79 387.117 746.003 382.851 736.238C378.585 726.474 376.366 715.94 376.329 705.286C376.291 694.63 378.439 684.084 382.637 674.29C386.835 664.497 392.995 655.662 400.737 648.34M473.829 705.014C473.829 710.399 469.464 714.764 464.079 714.764C458.694 714.764 454.329 710.399 454.329 705.014C454.329 699.629 458.694 695.264 464.079 695.264C469.464 695.264 473.829 699.629 473.829 705.014Z" stroke="#F5A623" stroke-width="12" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M374.538 790.583C362.848 779.683 353.516 766.502 347.117 751.856C340.718 737.209 337.385 721.414 337.329 705.431C337.273 689.447 340.494 673.611 346.791 658.92C353.087 644.228 362.333 630.981 373.946 619.999" stroke="#F5A623" stroke-width="12" stroke-linecap="round" stroke-linejoin="round" stroke-dasharray="24 24"/>
<path d="M1247.33 740.672C1252.2 736.13 1256.09 730.638 1258.75 724.535C1261.42 718.433 1262.8 711.843 1262.83 705.183C1262.85 698.524 1261.51 691.93 1258.89 685.809C1256.26 679.688 1252.41 674.168 1247.57 669.592M1277.03 762.057C1284.82 754.79 1291.04 746.003 1295.31 736.238C1299.57 726.474 1301.79 715.94 1301.83 705.286C1301.86 694.63 1299.72 684.084 1295.52 674.29C1291.32 664.497 1285.16 655.662 1277.42 648.34M1204.33 705.014C1204.33 710.399 1208.69 714.764 1214.08 714.764C1219.46 714.764 1223.83 710.399 1223.83 705.014C1223.83 699.629 1219.46 695.264 1214.08 695.264C1208.69 695.264 1204.33 699.629 1204.33 705.014Z" stroke="#F5A623" stroke-width="12" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M1303.62 790.583C1315.31 779.683 1324.64 766.502 1331.04 751.856C1337.44 737.209 1340.77 721.414 1340.83 705.431C1340.88 689.447 1337.66 673.611 1331.37 658.92C1325.07 644.228 1315.82 630.981 1304.21 619.999" stroke="#F5A623" stroke-width="12" stroke-linecap="round" stroke-linejoin="round" stroke-dasharray="24 24"/>
</svg>''';

/// The initial landing screen shown on first app launch.
///
/// Displays an illustration, a language selection grid, device status
/// indicators (hub strength and local storage usage), and a call-to-action
/// button that navigates to [LoginPage].
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
      final apkSize = AppInfoService.getApkSize();
      final totalSizeInMb = (sizeInBytes + apkSize) / (1024 * 1024);
      
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          if (totalSizeInMb < 1024) {
            _storageUsed = l10n.storageMbUsed(totalSizeInMb.toStringAsFixed(1));
          } else {
            _storageUsed = l10n.storageGbUsed((totalSizeInMb / 1024).toStringAsFixed(1));
          }
        });
      }
    } catch (e) {
      if (mounted) { final l10n = AppLocalizations.of(context)!; setState(() => _storageUsed = l10n.storageUnknown); }
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

  String _displayHubStrength(AppLocalizations l10n) {
    switch (_hubStrength) {
      case 'Checking...': return l10n.hubStrengthChecking;
      case 'Offline': return l10n.hubStrengthOffline;
      case 'Excellent': return l10n.hubStrengthExcellent;
      case 'Good': return l10n.hubStrengthGood;
      case 'Fair': return l10n.hubStrengthFair;
      default: return _hubStrength;
    }
  }

  String _displayStorageUsed(AppLocalizations l10n) {
    if (_storageUsed == 'Calculating...') return l10n.storageCalculating;
    if (_storageUsed == 'Unknown') return l10n.storageUnknown;
    return _storageUsed;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.xxl.w, vertical: AppSpacing.xxl.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const LuminaStepper(currentStep: 0),
                SizedBox(height: AppSpacing.section.h),
                _buildIllustration(context),
                SizedBox(height: AppSpacing.sectionLg.h),
                _buildContent(context),
                SizedBox(height: AppSpacing.section.h),
                _buildLanguageSelection(context),
                SizedBox(height: AppSpacing.touchTarget.h),
                _buildCTA(context),
                SizedBox(height: AppSpacing.sectionLg.h),
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
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      width: 312.w,
      height: 312.w,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg.r),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: EdgeInsets.all(AppSpacing.xxl.w),
      child: Stack(
        children: [
          Center(
            child: SvgPicture.string(
              _illustrationSvg,
              width: 240.w,
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.md.w, vertical: AppSpacing.sm.h),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sync, color: cs.secondary, size: 18.sp),
                    SizedBox(width: AppSpacing.sm.w),
                    Text(
                      l10n.illustrationBadgeNoInternet,
                      style: tt.labelSmall?.copyWith(
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
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        Text(
          l10n.welcomeTitle,
          textAlign: TextAlign.center,
          style: tt.displaySmall?.copyWith(
            color: cs.primary,
            height: 1.1,
          ),
        ),
        SizedBox(height: AppSpacing.md.h),
        Text(
          l10n.welcomeSubtitle,
          textAlign: TextAlign.center,
          style: tt.bodyLarge?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildLanguageSelection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.languageSectionHeader,
          style: tt.labelSmall?.copyWith(
            fontWeight: AppSpacing.weightStrong,
            color: cs.secondary,
            letterSpacing: 1.5,
          ),
        ),
        SizedBox(height: AppSpacing.md.h),
        Consumer(builder: (context, ref, child) {
          final currentLocale = ref.watch(localeProvider);
          final options = appLanguageOptions.where((o) => o['code'] != null).toList();
          return GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12.h,
            crossAxisSpacing: 12.w,
            childAspectRatio: 2.5,
            children: options.map((o) {
              final code = o['code']!;
              final isSelected = code == currentLocale.languageCode;
              String label;
              switch (code) {
                case 'en': label = l10n.languageEnglish; break;
                case 'hi': label = l10n.languageHindi; break;
                case 'kn': label = l10n.languageKannada; break;
                case 'fr': label = l10n.languageFrench; break;
                default: label = code;
              }
              return _LanguageButton(
                label: label,
                isSelected: isSelected,
                isEnabled: true,
                cs: cs,
                onTap: () => ref.read(localeProvider.notifier).setLocale(code),
              );
            }).toList(),
          );
        }),
      ],
    );
  }

  Widget _buildCTA(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LoginPage()),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: LuminaColors.ctaGold,
          foregroundColor: LuminaColors.ctaGoldText,
          padding: EdgeInsets.symmetric(vertical: AppSpacing.lg.h),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.r),
            side: const BorderSide(color: LuminaColors.ctaGoldBorder, width: 2),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              l10n.ctaEnterPortal,
              style: tt.titleLarge?.copyWith(
                fontWeight: AppSpacing.weightStrong,
              ),
            ),
            SizedBox(width: AppSpacing.sm.w),
            Icon(Icons.arrow_forward, size: 24.sp),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceStatus(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      padding: EdgeInsets.only(top: AppSpacing.xxl.h),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatusItem(
            icon: Icons.wifi,
            label: l10n.statusHubStrength,
            value: _displayHubStrength(l10n),
            cs: cs,
          ),
          _StatusItem(
            icon: Icons.storage,
            label: l10n.statusLocalStorage,
            value: _displayStorageUsed(l10n),
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
  final VoidCallback? onTap;

  const _LanguageButton({
    required this.label,
    required this.isSelected,
    required this.isEnabled,
    required this.cs,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: AppLocalizations.of(context)!.semanticsSelectLanguage(label),
      child: GestureDetector(
      onTap: (isEnabled && onTap != null) ? onTap : null,
      child: Container(
        decoration: BoxDecoration(
          color: isEnabled ? cs.onPrimary : cs.surfaceContainerHighest.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(
            color: isSelected 
                ? cs.primary 
                : (isEnabled ? cs.outlineVariant : cs.surfaceContainerHighest),
            width: isSelected ? 2 : 1,
          ),
        ),
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.md.w),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: tt.titleSmall?.copyWith(
                color: isSelected 
                    ? cs.primary 
                    : (isEnabled ? cs.onSurfaceVariant : cs.outline),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: cs.primary, size: 18.sp),
          ],
        ),
      ),
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
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(icon, color: cs.secondary, size: 24.sp),
        SizedBox(width: AppSpacing.sm.w),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: tt.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            Text(
              value.toUpperCase(),
              style: tt.labelSmall?.copyWith(
                fontWeight: AppSpacing.weightDisplay,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
