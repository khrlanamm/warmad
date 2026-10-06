import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Bottom navigation of the warung side.
class WarungShell extends StatelessWidget {
  const WarungShell({super.key, required this.navigationShell});

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
