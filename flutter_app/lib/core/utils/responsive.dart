import 'package:flutter/material.dart';

/// Breakpoints: mobile < 600 ≤ tablet < 1024 ≤ desktop
class R {
  R._();

  static const double _mobile = 600;
  static const double _desktop = 1024;

  static bool isMobile(BuildContext ctx) =>
      MediaQuery.of(ctx).size.width < _mobile;

  static bool isTablet(BuildContext ctx) {
    final w = MediaQuery.of(ctx).size.width;
    return w >= _mobile && w < _desktop;
  }

  static bool isDesktop(BuildContext ctx) =>
      MediaQuery.of(ctx).size.width >= _desktop;

  /// Pick a value based on screen tier.
  static T v<T>(BuildContext ctx,
      {required T mobile, required T tablet, required T desktop}) {
    if (isDesktop(ctx)) return desktop;
    if (isTablet(ctx)) return tablet;
    return mobile;
  }

  /// Horizontal page padding.
  static double hPad(BuildContext ctx) =>
      v<double>(ctx, mobile: 16, tablet: 24, desktop: 32);

  /// Symmetric page padding.
  static EdgeInsets pagePad(BuildContext ctx) => EdgeInsets.symmetric(
        horizontal: hPad(ctx),
        vertical: v<double>(ctx, mobile: 12, tablet: 16, desktop: 20),
      );

  /// Max width for centered content areas.
  static double maxWidth(BuildContext ctx) =>
      isDesktop(ctx) ? 1200 : (isTablet(ctx) ? 900 : double.infinity);

  /// Responsive dialog/sheet max width.
  static double dialogWidth(BuildContext ctx) =>
      (MediaQuery.of(ctx).size.width * 0.9).clamp(300.0, 560.0);

  /// Section card grid column count.
  static int sectionCols(BuildContext ctx) =>
      v<int>(ctx, mobile: 2, tablet: 3, desktop: 4);

  /// Section card aspect ratio.
  static double sectionAspect(BuildContext ctx) =>
      v<double>(ctx, mobile: 0.88, tablet: 1.0, desktop: 1.1);

  /// Grid spacing.
  static double gridSpacing(BuildContext ctx) =>
      v<double>(ctx, mobile: 12, tablet: 16, desktop: 20);
}
