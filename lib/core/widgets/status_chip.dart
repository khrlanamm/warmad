import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';

enum StatusTone { good, limited, warning, danger }

/// Small pill used for stock status, for example "Aman" or "Hampir habis".
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.tone});

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (tone) {
      StatusTone.good => (AppColors.greenTint, AppColors.greenDark),
      StatusTone.limited => (AppColors.yellowTint, AppColors.yellowDark),
      StatusTone.warning => (AppColors.warningTint, AppColors.warning),
      StatusTone.danger => (AppColors.dangerTint, AppColors.danger),
    };
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: background,
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          style: AppText.body(12, weight: FontWeight.w600, color: foreground),
        ),
      ),
    );
  }
}
