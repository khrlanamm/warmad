import 'package:flutter/material.dart';

abstract final class AppColors {
  /// Hijau Warung, the primary brand color.
  static const green = Color(0xFF1F6B45);
  static const greenDark = Color(0xFF17523A);
  static const greenTint = Color(0xFFE3EFE7);

  /// Kuning Terpal, the accent taken from the awning in the logo.
  static const yellow = Color(0xFFF4B51E);
  static const yellowDark = Color(0xFFC98A0A);
  static const yellowTint = Color(0xFFFDF1D3);

  /// Krem Etalase, the page background.
  static const cream = Color(0xFFFBF7EE);

  /// Tinta, the text color.
  static const ink = Color(0xFF1A2B22);
  static const inkMuted = Color(0xFF5C6B62);

  static const border = Color(0xFFE6E0D2);
  static const white = Color(0xFFFFFFFF);

  /// Low stock and other warnings.
  static const warning = Color(0xFFB4470F);
  static const warningTint = Color(0xFFFCE8DC);

  /// Out of stock and money going out.
  static const danger = Color(0xFFB42318);
  static const dangerTint = Color(0xFFFCE4E1);
}
