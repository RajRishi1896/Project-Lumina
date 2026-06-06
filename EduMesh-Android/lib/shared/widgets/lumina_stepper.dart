import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_spacing.dart';

/// A horizontal step indicator used in the welcome/onboarding flow.
///
/// Displays three labelled steps (Welcome, Login/Register, Access) as
/// numbered circles connected by lines. Completed steps show a checkmark
/// and are highlighted with the primary colour.
class LuminaStepper extends StatelessWidget {
  /// The index of the current active step (0-based).
  final int currentStep;

  const LuminaStepper({super.key, required this.currentStep});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final steps = ['Welcome', 'Login/Register', 'Access'];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(steps.length * 2 - 1, (index) {
        if (index.isEven) {
          final stepIndex = index ~/ 2;
          final isActive = stepIndex <= currentStep;
          final isPast = stepIndex < currentStep;
          
          return Column(
            children: [
              Container(
                width: 24.w,
                height: 24.w,
                decoration: BoxDecoration(
              color: isActive ? cs.primary : cs.surface,
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive ? cs.primary : cs.outlineVariant,
                width: 2,
              ),
            ),
            child: Center(
              child: isPast 
                ? Icon(Icons.check, color: cs.onPrimary, size: 14.sp)
                : Text(
                    '${stepIndex + 1}',
                    style: GoogleFonts.atkinsonHyperlegible(
                      fontSize: 12.sp,
                      fontWeight: AppSpacing.weightStrong,
                      color: isActive ? cs.onPrimary : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                steps[stepIndex],
                style: GoogleFonts.atkinsonHyperlegible(
                  fontSize: 10.sp,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  color: isActive ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ],
          );
        } else {
          final isActive = (index ~/ 2) < currentStep;
          return Container(
            width: 40.w,
            height: 2.h,
            margin: EdgeInsets.only(bottom: 14.h),
            color: isActive ? cs.primary : cs.outlineVariant,
          );
        }
      }),
    );
  }
}
