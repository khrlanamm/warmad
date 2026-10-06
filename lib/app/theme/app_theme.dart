import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppFonts {
  static const heading = 'BricolageGrotesque';
  static const body = 'DMSans';
}

/// Both fonts ship as variable fonts, so the weight axis has to be set
/// explicitly next to [FontWeight].
TextStyle _style(
  String family,
  double size,
  FontWeight weight, {
  double? height,
  Color color = AppColors.ink,
}) {
  return TextStyle(
    fontFamily: family,
    fontSize: size,
    fontWeight: weight,
    fontVariations: [FontVariation.weight(weight.value.toDouble())],
    height: height,
    color: color,
  );
}

abstract final class AppText {
  /// Rupiah amounts. Money is always set in the heading font.
  static TextStyle money(double size, {Color color = AppColors.ink}) => _style(
    AppFonts.heading,
    size,
    FontWeight.w700,
    height: 1.1,
    color: color,
  );

  static TextStyle heading(double size, {Color color = AppColors.ink}) =>
      _style(
        AppFonts.heading,
        size,
        FontWeight.w700,
        height: 1.2,
        color: color,
      );

  static TextStyle body(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.ink,
  }) => _style(AppFonts.body, size, weight, height: 1.4, color: color);
}

abstract final class AppTheme {
  static const _radius = 14.0;

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.green,
      onPrimary: AppColors.white,
      primaryContainer: AppColors.greenTint,
      onPrimaryContainer: AppColors.greenDark,
      secondary: AppColors.yellow,
      onSecondary: AppColors.ink,
      secondaryContainer: AppColors.yellowTint,
      onSecondaryContainer: AppColors.ink,
      error: AppColors.danger,
      onError: AppColors.white,
      errorContainer: AppColors.dangerTint,
      onErrorContainer: AppColors.danger,
      surface: AppColors.cream,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.inkMuted,
      outline: AppColors.border,
      outlineVariant: AppColors.border,
      surfaceContainerLowest: AppColors.white,
    );

    final textTheme = TextTheme(
      displaySmall: AppText.heading(32),
      headlineMedium: AppText.heading(26),
      headlineSmall: AppText.heading(22),
      titleLarge: AppText.heading(20),
      titleMedium: AppText.body(17, weight: FontWeight.w600),
      titleSmall: AppText.body(15, weight: FontWeight.w600),
      bodyLarge: AppText.body(16),
      bodyMedium: AppText.body(15),
      bodySmall: AppText.body(13, color: AppColors.inkMuted),
      labelLarge: AppText.body(16, weight: FontWeight.w600),
      labelMedium: AppText.body(14, weight: FontWeight.w500),
      labelSmall: AppText.body(12, weight: FontWeight.w500),
    );

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_radius),
    );
    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.cream,
      fontFamily: AppFonts.body,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.cream,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppText.heading(22),
      ),
      cardTheme: CardThemeData(
        color: AppColors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: shape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: shape,
          side: const BorderSide(color: AppColors.green, width: 1.5),
          foregroundColor: AppColors.green,
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.green,
          textStyle: textTheme.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: AppText.body(16, color: AppColors.inkMuted),
        border: inputBorder(AppColors.border),
        enabledBorder: inputBorder(AppColors.border),
        focusedBorder: inputBorder(AppColors.green, 1.5),
        errorBorder: inputBorder(AppColors.danger),
        focusedErrorBorder: inputBorder(AppColors.danger, 1.5),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.white,
        selectedColor: AppColors.green,
        side: const BorderSide(color: AppColors.border),
        shape: const StadiumBorder(),
        labelStyle: textTheme.labelMedium,
        showCheckmark: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.white,
        indicatorColor: AppColors.greenTint,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => AppText.body(
            12,
            weight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? AppColors.green
                : AppColors.inkMuted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.green
                : AppColors.inkMuted,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: AppText.body(15, color: AppColors.white),
        shape: shape,
      ),
    );
  }
}
