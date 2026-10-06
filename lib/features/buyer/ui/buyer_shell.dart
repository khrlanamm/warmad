import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../auth/data/auth_service.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/domain/user_profile.dart';

/// Bottom navigation of the buyer side.
class BuyerShell extends StatelessWidget {
  const BuyerShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: const [
          NavigationDestination(icon: Icon(LucideIcons.map), label: 'Peta'),
          NavigationDestination(icon: Icon(LucideIcons.search), label: 'Cari'),
          NavigationDestination(icon: Icon(LucideIcons.user), label: 'Akun'),
        ],
      ),
    );
  }
}

class BuyerAccountScreen extends ConsumerWidget {
  const BuyerAccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(authServiceProvider).currentUser;
    final name = user?.displayName ?? 'Pembeli';

    return Scaffold(
      appBar: AppBar(title: const Text('Akun')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppColors.greenTint,
                    child: Text(
                      name.isEmpty ? '' : name[0].toUpperCase(),
                      style: AppText.heading(18, color: AppColors.green),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: theme.textTheme.titleLarge),
                        Text(
                          user?.email ?? '',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: user == null
                ? null
                : () => ref
                      .read(profileRepositoryProvider)
                      .setMode(user, AppMode.warung, isNew: false),
            icon: const Icon(LucideIcons.store),
            label: const Text('Punya warung? Beralih ke pemilik'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger),
            ),
            onPressed: () => ref.read(authServiceProvider).signOut(),
            icon: const Icon(LucideIcons.logOut),
            label: const Text('Keluar akun'),
          ),
        ],
      ),
    );
  }
}
