import 'package:flutter/material.dart';

/// A 4px-based spacing grid and standardised typography weights for the app.
class AppSpacing {
  AppSpacing._();

  /// 4px -- The base unit of the spacing grid.
  static const double xs = 4;

  /// 8px -- Small spacing between related elements.
  static const double sm = 8;

  /// 12px -- Medium spacing for element groups.
  static const double md = 12;

  /// 16px -- Large spacing, used for card padding.
  static const double lg = 16;

  /// 20px -- Extra-large spacing.
  static const double xl = 20;

  /// 24px -- Double extra-large spacing.
  static const double xxl = 24;

  /// 32px -- Section-level spacing between distinct content blocks.
  static const double section = 32;

  /// 40px -- Large section spacing.
  static const double sectionLg = 40;

  /// 48px -- Minimum touch target size for interactive elements.
  static const double touchTarget = 48;

  /// 64px -- Standard page horizontal margin.
  static const double pageMargin = 64;

  /// 4px -- Small border radius.
  static const double radiusSm = 4;

  /// 8px -- Medium border radius.
  static const double radiusMd = 8;

  /// 12px -- Large border radius.
  static const double radiusLg = 12;

  /// 16px -- Extra-large border radius.
  static const double radiusXl = 16;

  /// 24px -- Pill-like border radius for compact overlay panels.
  static const double radiusPill = 24;

  /// 9999px -- Fully rounded (pill/circle) border radius.
  static const double radiusFull = 9999;

  /// 144px -- Mini player overlay width.
  static const double miniPlayerWidth = 144;

  /// 80px -- Mini player overlay height.
  static const double miniPlayerHeight = 80;

  /// 2px -- Hairline value, used for shadow offsets and thin dividers.
  static const double hairline = 2;

  /// Font weight 400 -- Used for body text.
  static const FontWeight weightBody = FontWeight.w400;

  /// Font weight 700 -- Used for strong emphasis and headings.
  static const FontWeight weightStrong = FontWeight.w700;

  /// Font weight 800 -- Used for display and title text.
  static const FontWeight weightDisplay = FontWeight.w800;
}
