import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/date_labels.dart';
import '../../profile/data/profile_repository.dart';
import '../data/notification_repository.dart';

/// Notifikasi: stock alerts, cash closings and reminders for the owner.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notifications = ref.watch(notificationsProvider);
    final list = notifications.value ?? const <AppNotification>[];
    final unread = list.where((n) => !n.read).map((n) => n.id).toList();
    final now = DateTime.now();

    // Keeps the order of the list while grouping it by day.
    final groups = <String, List<AppNotification>>{};
    for (final notification in list) {
      groups
          .putIfAbsent(dayGroupOf(notification.createdAt, now), () => [])
          .add(notification);
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Kembali',
          onPressed: () => context.pop(),
          icon: const Icon(LucideIcons.chevronLeft),
        ),
        title: const Text('Notifikasi'),
        actions: [
          if (unread.isNotEmpty)
            TextButton(
              onPressed: () {
                final warungId = ref.read(membershipProvider).value?.warungId;
                if (warungId == null) return;
                ref
                    .read(notificationRepositoryProvider)
                    .markRead(warungId, unread);
              },
              child: const Text('Tandai dibaca'),
            ),
        ],
      ),
      body: !notifications.hasValue
          ? const Center(child: CircularProgressIndicator())
          : list.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Belum ada notifikasi. Kabar stok hampir habis dan tutup '
                  'kas muncul di sini.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: AppColors.inkMuted,
                  ),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              children: [
                for (final group in groups.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 8),
                    child: Text(
                      group.key,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final (index, item) in group.value.indexed) ...[
                          if (index > 0) const Divider(),
                          _NotificationTile(notification: item, now: now),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.now});

  final AppNotification notification;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color, background) = switch (notification.type) {
      'outOfStock' => (
        LucideIcons.package,
        AppColors.danger,
        AppColors.dangerTint,
      ),
      'lowStock' => (
        LucideIcons.triangleAlert,
        AppColors.warning,
        AppColors.warningTint,
      ),
      'cashClosed' => (
        LucideIcons.banknote,
        AppColors.warning,
        AppColors.warningTint,
      ),
      _ => (LucideIcons.clock, AppColors.green, AppColors.greenTint),
    };
    final productId = notification.productId;

    return Material(
      // Unread entries are tinted so they stand out.
      color: notification.read ? AppColors.white : AppColors.yellowTint,
      child: InkWell(
        onTap: switch (notification.type) {
          'lowStock' || 'outOfStock' when productId != null =>
            () => context.push(Routes.warungProduct(productId)),
          'cashClosed' => () => context.push(Routes.warungCashHistory),
          'closingReminder' => () => context.push(Routes.warungCashClosing),
          _ => null,
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(9),
                  child: Icon(icon, size: 20, color: color),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(notification.title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      notification.body,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.inkMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatRelative(notification.createdAt, now),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (!notification.read)
                const Padding(
                  padding: EdgeInsets.only(left: 8, top: 4),
                  child: CircleAvatar(
                    radius: 5,
                    backgroundColor: AppColors.yellow,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
