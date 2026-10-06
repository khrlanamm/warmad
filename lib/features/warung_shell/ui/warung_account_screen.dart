import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../auth/data/auth_service.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/domain/user_profile.dart';
import '../../warung/data/warung_repository.dart';

/// Akun dan warung: warung profile, map visibility, and account actions.
class WarungAccountScreen extends ConsumerWidget {
  const WarungAccountScreen({super.key});

  static String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return words.take(2).map((w) => w[0].toUpperCase()).join();
  }

  /// Lets the owner pick the reminder time or turn it off. The time snaps
  /// to a quarter hour, which is how often the server checks.
  Future<void> _editReminder(
    BuildContext context,
    WidgetRef ref,
    String warungId,
    String? current,
  ) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.cream,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.clock),
              title: const Text('Pilih jam pengingat'),
              onTap: () => Navigator.of(context).pop('pick'),
            ),
            if (current != null)
              ListTile(
                leading: const Icon(LucideIcons.bellOff),
                title: const Text('Matikan pengingat'),
                onTap: () => Navigator.of(context).pop('off'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;

    final repository = ref.read(warungRepositoryProvider);
    if (choice == 'off') {
      await repository.setCashReminder(warungId, null);
      return;
    }
    final parts = (current ?? '21:00').split(':').map(int.parse).toList();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: parts[0], minute: parts[1]),
      helpText: 'Ingatkan tutup kas pada jam',
    );
    if (picked == null) return;
    final minute = (picked.minute ~/ 15) * 15;
    await repository.setCashReminder(
      warungId,
      '${picked.hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final warung = ref.watch(currentWarungProvider).value;
    final membership = ref.watch(membershipProvider).value;
    final user = ref.watch(authServiceProvider).currentUser;
    final isOwner = membership?.isOwner ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Akun dan warung')),
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
                    backgroundColor: AppColors.green,
                    child: Text(
                      _initials(warung?.name ?? ''),
                      style: AppText.heading(18, color: AppColors.white),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          warung?.name ?? '',
                          style: theme.textTheme.titleLarge,
                        ),
                        Text(
                          warung?.address ?? '',
                          style: theme.textTheme.bodySmall,
                        ),
                        Text(
                          '${isOwner ? 'Pemilik' : 'Kasir'}: '
                          '${user?.displayName ?? user?.email ?? ''}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isOwner && warung != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(
                        LucideIcons.map,
                        color: AppColors.green,
                      ),
                      title: Text(
                        'Tampilkan warung di peta',
                        style: theme.textTheme.titleSmall,
                      ),
                      value: warung.showOnMap,
                      onChanged: (value) => ref
                          .read(warungRepositoryProvider)
                          .setShowOnMap(warung.id, value),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        'Pembeli hanya melihat status barang (tersedia, '
                        'terbatas, habis). Jumlah stok dan kas tidak pernah '
                        'ditampilkan.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ListTile(
                    title: const Text('Jam buka'),
                    trailing: Text(
                      warung.hours.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    title: const Text('Pengingat tutup kas'),
                    trailing: Text(
                      warung.cashReminderTime?.replaceAll(':', '.') ?? 'Mati',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.inkMuted,
                      ),
                    ),
                    onTap: () => _editReminder(
                      context,
                      ref,
                      warung.id,
                      warung.cashReminderTime,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  title: const Text('Kasbon pelanggan'),
                  trailing: const Icon(LucideIcons.chevronRight),
                  onTap: () => context.push(Routes.warungCustomers),
                ),
                const Divider(),
                ListTile(
                  title: const Text('Pemasok dan utang'),
                  trailing: const Icon(LucideIcons.chevronRight),
                  onTap: () => context.push(Routes.warungSuppliers),
                ),
                const Divider(),
                ListTile(
                  title: const Text('Riwayat penjualan'),
                  trailing: const Icon(LucideIcons.chevronRight),
                  onTap: () => context.push(Routes.warungSales),
                ),
                const Divider(),
                ListTile(
                  title: const Text('Riwayat tutup kas'),
                  trailing: const Icon(LucideIcons.chevronRight),
                  onTap: () => context.push(Routes.warungCashHistory),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: user == null
                ? null
                : () => ref
                      .read(profileRepositoryProvider)
                      .setMode(user, AppMode.pembeli, isNew: false),
            icon: const Icon(LucideIcons.mapPin),
            label: const Text('Beralih ke mode pembeli'),
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
