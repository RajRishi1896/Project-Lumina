import 'package:flutter/material.dart';

/// A reusable styled [ElevatedButton] with optional full-width layout.
///
/// Wraps the standard [ElevatedButton] with configurable background and
/// foreground colours. When [isFullWidth] is true (default), the button
/// expands to fill the available horizontal space.
class LuminaButton extends StatelessWidget {
  /// The text label displayed on the button.
  final String label;

  /// The callback invoked when the button is pressed.
  final VoidCallback onPressed;

  /// The background colour of the button.
  final Color? backgroundColor;

  /// The foreground (text) colour of the button.
  final Color? foregroundColor;

  /// Whether the button should take full width. Defaults to `true`.
  final bool isFullWidth;

  const LuminaButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
    this.isFullWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    final button = ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        minimumSize: const Size(48, 48), // Touch target compliance
      ),
      child: Text(label),
    );

    if (isFullWidth) {
      return SizedBox(
        width: double.infinity,
        child: button,
      );
    }

    return button;
  }
}
