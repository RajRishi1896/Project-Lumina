import 'package:flutter/material.dart';

/// A reusable bordered card container with optional tap handling.
///
/// Wraps [child] in an [AnimatedContainer] with a configurable border colour,
/// border width, and padding. Supports an optional [onTap] callback for
/// interaction.
class LuminaCard extends StatelessWidget {
  /// The widget placed inside the card.
  final Widget child;

  /// The padding around [child]. Defaults to `EdgeInsets.all(16)`.
  final EdgeInsetsGeometry? padding;

  /// The border colour. Defaults to `cs.outlineVariant`.
  final Color? borderColor;

  /// The border width. Defaults to `1.0`.
  final double borderWidth;

  /// An optional callback invoked when the card is tapped.
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
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: borderColor ?? cs.outlineVariant,
            width: borderWidth,
          ),
        ),
        child: child,
      ),
    );
  }
}
