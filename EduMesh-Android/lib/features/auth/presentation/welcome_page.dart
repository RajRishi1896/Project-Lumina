import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:edumesh_android/core/navigation/lumina_transitions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'login_page.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/lumina_colors.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../shared/services/connectivity_service.dart';
import '../../../shared/widgets/lumina_stepper.dart';
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
  int? _hubResourceCount;
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

    // 2. Fetch hub resource count for the status row (public /stats endpoint)
    if (isConnected) {
      try {
        final resp = await ApiClient.get<Map<String, dynamic>>('/stats')
            .timeout(const Duration(seconds: 3));
        final count = resp.data?['resources'];
        if (mounted) {
          setState(() {
            _hubResourceCount = count is num ? count.toInt() : null;
          });
        }
      } catch (_) {
        // Stats fetch failed: hide the resources row
      }
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
    // ponytail: clamp hero square to viewport so landscape never crops it.
    final size = MediaQuery.sizeOf(context);
    final side = math.max(120.0, math.min(312.w, math.min(size.width * 0.85, size.height * 0.5)));

    return Container(
      width: side,
      height: side,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg.r),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Stack(
        children: [
          Center(
            child: SvgPicture.asset(
              _illustrationSvg,
              width: side - AppSpacing.xxl * 2,
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8.r),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sync, color: cs.secondary, size: 18.sp),
                      const SizedBox(width: AppSpacing.sm),
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
          const allOptions = appLanguageOptions;
          const primaryCount = 3;
          final primaryItems = allOptions.sublist(0, primaryCount);

          return Column(
            children: [
              // ponytail: clamp tile height so landscape width can't balloon the cards.
              LayoutBuilder(
                builder: (context, constraints) {
                  final tileW = (constraints.maxWidth - 12.w) / 2;
                  final tileH = (tileW / 2.5).clamp(56.0, 72.0);
                  return GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 12.h,
                    crossAxisSpacing: 12.w,
                    childAspectRatio: tileW / tileH,
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
                  );
                },
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
            luminaRoute(builder: (_) => const LoginPage()),
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

    final rows = <Widget>[
      Flexible(child: _StatusItem(
        icon: Icons.wifi,
        label: l10n.statusHubStrength,
        value: hubText,
        cs: cs,
      )),
    ];
    // Hidden entirely when offline or the /stats fetch failed
    final resourceCount = _hubResourceCount;
    if (resourceCount != null) {
      rows.add(Flexible(child: _StatusItem(
        icon: Icons.library_books,
        label: l10n.statusHubResources,
        value: l10n.welcomeHubResources(resourceCount),
        cs: cs,
      )));
    }

    return Container(
      padding: EdgeInsets.only(top: AppSpacing.xxl.h),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: rows,
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
  showLuminaDialog(
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
