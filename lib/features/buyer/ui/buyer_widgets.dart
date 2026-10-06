import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/date_labels.dart';
import '../../../core/widgets/status_chip.dart';
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

/// "250 m, buka 24 jam" style summary of a warung.
String describeWarung(PublicWarung warung, DateTime now) {
  final open = isOpenAt(warung.hours, now);
  final hours = warung.hours.is24h
      ? 'buka 24 jam'
      : open
      ? 'buka sampai ${warung.hours.close?.replaceAll(':', '.')}'
      : 'tutup, buka ${warung.hours.open?.replaceAll(':', '.')}';
  final distance = warung.distance;
  return distance == null ? hours : '${formatDistance(distance)}, $hours';
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
