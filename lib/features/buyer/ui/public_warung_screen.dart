import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_colors.dart';
import '../data/buyer_repository.dart';
import '../domain/geo.dart';
import '../domain/public_warung.dart';
import 'buyer_widgets.dart';

/// Detail warung for buyers: where it is, when it is open, and which goods
/// it has. Statuses only, never stock counts.
class PublicWarungScreen extends ConsumerStatefulWidget {
  const PublicWarungScreen({super.key, required this.warungId, this.warung});

  final String warungId;

  /// Passed along from the map or the search, which already loaded it.
  final PublicWarung? warung;

  @override
  ConsumerState<PublicWarungScreen> createState() => _PublicWarungScreenState();
}

class _PublicWarungScreenState extends ConsumerState<PublicWarungScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warung =
        widget.warung ??
        ref
            .watch(nearbyWarungsProvider)
            .value
            ?.where((w) => w.id == widget.warungId)
            .firstOrNull;
    if (warung == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Warung tidak ditemukan.')),
      );
    }

    final now = DateTime.now();
    final items = ref.watch(publicItemsProvider(warung.id));
    final words = _query.toLowerCase().trim().split(RegExp(r'\s+'));
    final visible = (items.value ?? const <PublicItem>[]).where((item) {
      final name = item.name.toLowerCase();
      return words.every(name.contains);
    }).toList();
    final distance = warung.distance;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 190,
            backgroundColor: AppColors.cream,
            leading: Padding(
              padding: const EdgeInsets.all(6),
              child: IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.white,
                  foregroundColor: AppColors.ink,
                ),
                tooltip: 'Kembali',
                onPressed: () => context.pop(),
                icon: const Icon(LucideIcons.chevronLeft),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: LatLng(warung.lat, warung.lng),
                  zoom: 16,
                ),
                // A picture of where the warung is, not a map to explore.
                liteModeEnabled: true,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                myLocationButtonEnabled: false,
                markers: {
                  Marker(
                    markerId: MarkerId(warung.id),
                    position: LatLng(warung.lat, warung.lng),
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueYellow,
                    ),
                  ),
                },
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            sliver: SliverList.list(
              children: [
                Text(warung.name, style: theme.textTheme.headlineMedium),
                Text(
                  warung.address,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.inkMuted,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    if (distance != null)
                      _Fact(LucideIcons.mapPin, formatDistance(distance)),
                    _Fact(
                      LucideIcons.clock,
                      describeWarung(warung, now).split(', ').last,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () => openDirections(warung),
                  icon: const Icon(LucideIcons.navigation),
                  label: const Text('Petunjuk arah'),
                ),
                const SizedBox(height: 22),
                Text('Barang di warung ini', style: theme.textTheme.titleLarge),
                const SizedBox(height: 10),
                TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    hintText: 'Cek barang di sini',
                    prefixIcon: Icon(LucideIcons.search),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 4,
                      backgroundColor: AppColors.green,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      describeFreshness(warung, now),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (items.hasError)
                  Text(
                    'Gagal memuat barang. Cek internet, lalu coba lagi.',
                    style: theme.textTheme.bodyMedium,
                  )
                else if (!items.hasValue)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (visible.isEmpty)
                  Text(
                    _query.trim().isEmpty
                        ? 'Warung ini belum mendaftarkan barang.'
                        : 'Barang itu tidak ada di daftar warung ini.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.inkMuted,
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (final (index, item) in visible.indexed) ...[
                          if (index > 0) const Divider(),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.name,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: item.status == Availability.habis
                                          ? AppColors.inkMuted
                                          : AppColors.ink,
                                    ),
                                  ),
                                ),
                                AvailabilityChip(item.status),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                const AvailabilityDisclaimer(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: AppColors.green),
        const SizedBox(width: 6),
        Text(text, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
