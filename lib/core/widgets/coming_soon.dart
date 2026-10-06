import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Stand-in body for a tab whose feature is built in a later milestone.
class ComingSoon extends StatelessWidget {
  const ComingSoon({super.key, required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.border),
            const SizedBox(height: 12),
            Text(
              'Segera hadir',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: AppColors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
