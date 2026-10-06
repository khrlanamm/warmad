import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/money.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/widgets/terpal_card.dart';
import '../../auth/data/auth_service.dart';

/// Temporary landing screen. It only proves the theme and sign in work and is
/// replaced by the role selection flow.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(authServiceProvider).currentUser;
    final muted = AppColors.white.withValues(alpha: 0.8);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Warmad'),
        actions: [
          IconButton(
            tooltip: 'Keluar akun',
            onPressed: () => ref.read(authServiceProvider).signOut(),
            icon: const Icon(LucideIcons.logOut),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Halo, ${user?.displayName ?? 'Pengguna'}',
            style: theme.textTheme.headlineSmall,
          ),
          Text(user?.email ?? '', style: theme.textTheme.bodySmall),
          const SizedBox(height: 20),
          TerpalCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kas usaha hari ini',
                  style: AppText.body(14, color: muted),
                ),
                const SizedBox(height: 4),
                Text(
                  formatRupiah(0),
                  style: AppText.money(34, color: AppColors.white),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusChip(label: 'Aman', tone: StatusTone.good),
                  StatusChip(label: 'Terbatas', tone: StatusTone.limited),
                  StatusChip(label: 'Hampir habis', tone: StatusTone.warning),
                  StatusChip(label: 'Habis', tone: StatusTone.danger),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
