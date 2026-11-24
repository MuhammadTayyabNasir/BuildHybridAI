import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const primary = Color(0xFFE8431F); // PMA ember
  static const primaryLight = Color(0xFFFF6A3D); // PMA flame
  static const primaryDark = Color(0xFFAC1900);

  static const secondary = Color(0xFFFFC107);
  static const secondaryLight = Color(0xFFFFF350);
  static const secondaryDark = Color(0xFFC79100);

  static const backgroundLight = Color(0xFFF6F3F1); // PMA canvas
  static const backgroundDark = Color(0xFF121212);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceDark = Color(0xFF1E1E1E);
  static const cardDark = Color(0xFF2C2C2C);

  static const green = Color(0xFF4CAF50);
  static const greenLight = Color(0xFFE8F5E9);
  static const greenDark = Color(0xFF1B5E20);

  static const yellow = Color(0xFFFFB300);
  static const yellowLight = Color(0xFFFFF8E1);
  static const yellowDark = Color(0xFF7B6000);

  static const red = Color(0xFFF44336);
  static const redLight = Color(0xFFFFEBEE);
  static const redDark = Color(0xFFB71C1C);

  static const chips = Color(0xFFE65100);
  static const periPeri = Color(0xFFD32F2F);
  static const nimko = Color(0xFF388E3C);
  static const wafer = Color(0xFF1565C0);
  static const chocolate = Color(0xFF4E342E);

  static const textPrimary = Color(0xFF212121);
  static const textSecondary = Color(0xFF757575);
  static const textHint = Color(0xFFBDBDBD);

  static const divider = Color(0xFFE0E0E0);
  static const shadow = Color(0x1A000000);

  static Color statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'green':
        return green;
      case 'yellow':
        return yellow;
      case 'red':
        return red;
      default:
        return textSecondary;
    }
  }

  static Color statusBg(String status, bool isDark) {
    switch (status.toLowerCase()) {
      case 'green':
        return isDark ? greenDark.withValues(alpha: 0.3) : greenLight;
      case 'yellow':
        return isDark ? yellowDark.withValues(alpha: 0.3) : yellowLight;
      case 'red':
        return isDark ? redDark.withValues(alpha: 0.3) : redLight;
      default:
        return Colors.transparent;
    }
  }

  static Color sectionColor(String section) {
    switch (section.toLowerCase()) {
      case 'chips':
        return chips;
      case 'peri_peri':
        return periPeri;
      case 'nimko':
        return nimko;
      case 'wafer':
        return wafer;
      case 'chocolate':
        return chocolate;
      default:
        return primary;
    }
  }
}
