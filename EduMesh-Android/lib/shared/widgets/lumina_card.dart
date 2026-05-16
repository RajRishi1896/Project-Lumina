import 'package:flutter/material.dart';
import '../../core/constants/lumina_colors.dart';

class LuminaCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? borderColor;
  final double borderWidth;
  final VoidCallback? onTap;

  const LuminaCard({
    super.key,
    required this.child,
    this.padding,
    this.borderColor,
    this.borderWidth = 1.0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: borderColor ?? LuminaColors.outline,
            width: borderWidth,
          ),
        ),
        child: child,
      ),
    );
  }
}
