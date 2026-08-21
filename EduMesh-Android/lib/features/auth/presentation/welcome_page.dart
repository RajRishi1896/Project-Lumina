import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';
import 'login_page.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/lumina_colors.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../shared/services/connectivity_service.dart';
import '../../../shared/widgets/lumina_stepper.dart';
import '../../../core/utils/file_utils.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';

const _illustrationSvg = 'assets/images/illustration.svg';

/// Onboarding flow with language selection, captive portal guide, and display
/// name setup.
class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  bool _isConnected = false;
  int _latencyMs = 0;
  double? _storageUsedMb;
  final ConnectivityService _connectivityService = ConnectivityService();

  @override
  void initState() {
    super.initState();
    _fetchSystemStatus();
  }

  Future<void> _fetchSystemStatus() async {
    // 1. Check Hub Strength (via latency)
    final stopwatch = Stopwatch()..start();
    final isConnected = await _connectivityService.ping(timeout: const Duration(seconds: 2));
    stopwatch.stop();

    if (mounted) {
      setState(() {
        _isConnected = isConnected;
        _latencyMs = stopwatch.elapsedMilliseconds;
      });
    }

    // 2. Calculate Local Storage Used (including APK)
    try {
      const channel = MethodChannel('com.edumesh.android/storage');
      final info = await channel.invokeMethod<Map>('getStorageInfo');
      final apkSize = info?['apkSize'] as int?;
      if (apkSize == null || apkSize <= 0) throw StateError('no apk size');
      final dir = await getApplicationDocumentsDirectory();
      final sizeInBytes = await getDirSize(dir);
      final totalSizeInMb = (sizeInBytes + apkSize) / (1024 * 1024);

      if (mounted) {
        setState(() {
          _storageUsedMb = totalSizeInMb;
        });
      }
    } catch (_) {
      // Storage calc failed: leave null
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
            child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.xxl.w, vertical: AppSpacing.xxl.h),
            child: Column(
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
            child: SvgPicture.asset(
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
          final allOptions = appLanguageOptions;
          const primaryCount = 3;
          final primaryItems = allOptions.sublist(0, primaryCount);

          return Column(
            children: [
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 12.h,
                crossAxisSpacing: 12.w,
                childAspectRatio: 2.5,
                children: [
                  ...primaryItems.map((o) {
                    final code = o['code']!;
                    final label = o['label'] ?? code;
                    final isSelected = code == currentLocale.languageCode;
                    return _LanguageButton(
                      label: label,
                      isSelected: isSelected,
                      isEnabled: true,
                      cs: cs,
                      onTap: () => ref.read(localeProvider.notifier).setLocale(code),
                    );
                  }),
                  _LanguageButton(
                    label: l10n.moreLanguages,
                    isSelected: false,
                    isEnabled: true,
                    cs: cs,
                    onTap: () => _showMoreLanguages(context, ref, allOptions, currentLocale, l10n, cs),
                  ),
                ],
              ),
            ],
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

    String hubText;
    if (!_isConnected && _latencyMs == 0) {
      hubText = l10n.hubStrengthChecking;
    } else if (!_isConnected) {
      hubText = l10n.hubStrengthOffline;
    } else if (_latencyMs < 50) {
      hubText = l10n.hubStrengthExcellent;
    } else if (_latencyMs < 150) {
      hubText = l10n.hubStrengthGood;
    } else {
      hubText = l10n.hubStrengthFair;
    }

    String storageText;
    if (_storageUsedMb == null) {
      storageText = l10n.storageCalculating;
    } else if (_storageUsedMb! < 1024) {
      storageText = l10n.storageMbUsed(_storageUsedMb!.toStringAsFixed(1));
    } else {
      storageText = l10n.storageGbUsed((_storageUsedMb! / 1024).toStringAsFixed(1));
    }

    return Container(
      padding: EdgeInsets.only(top: AppSpacing.xxl.h),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Flexible(child: _StatusItem(
            icon: Icons.wifi,
            label: l10n.statusHubStrength,
            value: hubText,
            cs: cs,
          )),
          Flexible(child: _StatusItem(
            icon: Icons.storage,
            label: l10n.statusLocalStorage,
            value: storageText,
            cs: cs,
          )),
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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

void _showMoreLanguages(
  BuildContext context,
  WidgetRef ref,
  List<Map<String, String?>> allLanguages,
  Locale currentLocale,
  AppLocalizations l10n,
  ColorScheme cs,
) {
  showDialog(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(l10n.settingsLanguagePickerTitle),
      children: allLanguages.map((o) {
        final code = o['code']!;
        final label = o['label'] ?? code;
        final isSelected = code == currentLocale.languageCode;
        return ListTile(
          leading: isSelected
              ? Icon(Icons.check, color: cs.primary)
              : const SizedBox(width: AppSpacing.xxl),
          title: Text(label),
          onTap: () {
            ref.read(localeProvider.notifier).setLocale(code);
            Navigator.pop(ctx);
          },
        );
      }).toList(),
    ),
  );
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
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              Text(
                value.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.labelSmall?.copyWith(
                  fontWeight: AppSpacing.weightDisplay,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
