import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/date_labels.dart';
import '../../../core/widgets/status_chip.dart';
import '../data/buyer_repository.dart';
import '../domain/geo.dart';
import '../domain/public_warung.dart';

/// Pill showing Tersedia, Terbatas or Habis.
class AvailabilityChip extends StatelessWidget {
  const AvailabilityChip(this.status, {super.key});

  final Availability status;

  @override
  Widget build(BuildContext context) {
    return StatusChip(
      label: status.label,
      tone: switch (status) {
        Availability.tersedia => StatusTone.good,
        Availability.terbatas => StatusTone.limited,
        Availability.habis => StatusTone.danger,
      },
    );
  }
}

/// "buka 24 jam", "buka sampai 21.00" or "tutup, buka 06.00".
String describeHours(PublicWarung warung, DateTime now) {
  if (warung.hours.is24h) return 'buka 24 jam';
  return isOpenAt(warung.hours, now)
      ? 'buka sampai ${warung.hours.close?.replaceAll(':', '.')}'
      : 'tutup, buka ${warung.hours.open?.replaceAll(':', '.')}';
}

/// "250 m, buka 24 jam" style summary of a warung.
String describeWarung(PublicWarung warung, DateTime now) {
  final hours = describeHours(warung, now);
  final distance = warung.distance;
  return distance == null ? hours : '${formatDistance(distance)}, $hours';
}

/// Where distances are measured from when the buyer's position is unknown.
const fallbackPlaceName = 'Telang, Kamal';

/// "4 warung dalam 5 km · terdekat 350 m" style summary of a search.
/// [warungs] is nearest first; [openOnly] says the list holds only warungs
/// that are open now.
String describeNearby(
  List<PublicWarung> warungs,
  int radiusKm, {
  required bool located,
  bool openOnly = false,
}) {
  // Non-breaking spaces keep a number and its unit on one line.
  final count = '${warungs.length} warung${openOnly ? ' buka' : ''}';
  final radius = '$radiusKm\u00a0km';
  if (!located) return '$count dalam $radius dari $fallbackPlaceName';
  final nearest = warungs.firstOrNull?.distance;
  return nearest == null
      ? '$count dalam $radius'
      : '$count dalam $radius · terdekat '
            '${formatDistance(nearest).replaceAll(' ', '\u00a0')}';
}

/// When the warung last recorded anything, so buyers can judge how fresh
/// the availability is.
String describeFreshness(PublicWarung warung, DateTime now) {
  final lastActive = warung.lastActiveAt;
  if (lastActive == null) return 'Status belum pernah diperbarui';
  return 'Status diperbarui ${formatRelativeInline(lastActive, now)}';
}

/// The note the spec asks for wherever availability is shown.
class AvailabilityDisclaimer extends StatelessWidget {
  const AvailabilityDisclaimer({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      'Status diisi pemilik warung dan bisa berbeda dengan kondisi di toko.',
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: AppColors.inkMuted),
    );
  }
}

/// Opens the phone's maps app with directions to [warung].
Future<void> openDirections(PublicWarung warung) {
  return launchUrl(
    Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=${warung.lat},${warung.lng}',
    ),
    mode: LaunchMode.externalApplication,
  );
}

/// Chip showing the search radius. Tapping it lets the buyer pick another.
class RadiusChip extends ConsumerWidget {
  const RadiusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final km = ref.watch(buyerRadiusProvider);
    return ActionChip(
      avatar: const Icon(LucideIcons.radar, size: 16, color: AppColors.green),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$km km'),
          const SizedBox(width: 2),
          const Icon(LucideIcons.chevronDown, size: 16),
        ],
      ),
      tooltip: 'Jarak pencarian',
      onPressed: () => _pick(context, ref, km),
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref, int current) async {
    final theme = Theme.of(context);
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
              child: Text('Jarak pencarian', style: theme.textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'Warung dalam jarak ini tampil di peta dan dipakai saat '
                'mencari barang.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.inkMuted,
                ),
              ),
            ),
            for (final km in radiusOptionsKm)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                title: Text(
                  'Dalam $km km',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: km == current ? FontWeight.w600 : null,
                  ),
                ),
                trailing: km == current
                    ? const Icon(LucideIcons.check, color: AppColors.green)
                    : null,
                onTap: () => Navigator.pop(context, km),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) ref.read(buyerRadiusProvider.notifier).set(picked);
  }
}
