import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

class LuminaStepper extends StatelessWidget {
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
                  color: isActive ? cs.primary : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isActive ? cs.primary : cs.outlineVariant,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: isPast 
                    ? Icon(Icons.check, color: Colors.white, size: 14.sp)
                    : Text(
                        '${stepIndex + 1}',
                        style: GoogleFonts.atkinsonHyperlegible(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.bold,
                          color: isActive ? Colors.white : cs.onSurfaceVariant,
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
