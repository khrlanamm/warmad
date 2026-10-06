import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../notifications/data/push_service.dart';
import '../../profile/data/profile_repository.dart';

/// Bottom navigation of the warung side.
class WarungShell extends ConsumerStatefulWidget {
  const WarungShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<WarungShell> createState() => _WarungShellState();
}

class _WarungShellState extends ConsumerState<WarungShell> {
  @override
  void initState() {
    super.initState();
    // Stock alerts and closing reminders reach the owner as pushes.
    final uid = ref.read(currentUidProvider);
    if (uid != null) ref.read(pushServiceProvider).register(uid);
  }

  @override
  Widget build(BuildContext context) {
    final navigationShell = widget.navigationShell;
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(LucideIcons.house),
            label: 'Beranda',
          ),
          NavigationDestination(
            icon: Icon(LucideIcons.shoppingCart),
            label: 'Kasir',
          ),
          NavigationDestination(icon: Icon(LucideIcons.package), label: 'Stok'),
          NavigationDestination(
            icon: Icon(LucideIcons.chartColumn),
            label: 'Laporan',
          ),
          NavigationDestination(icon: Icon(LucideIcons.user), label: 'Akun'),
        ],
      ),
    );
  }
}
