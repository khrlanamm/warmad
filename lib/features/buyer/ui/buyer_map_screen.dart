import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../data/buyer_repository.dart';
import '../domain/public_warung.dart';
import 'buyer_widgets.dart';

/// Peta: warungs around the buyer.
class BuyerMapScreen extends ConsumerStatefulWidget {
  const BuyerMapScreen({super.key});

  @override
  ConsumerState<BuyerMapScreen> createState() => _BuyerMapScreenState();
}

class _BuyerMapScreenState extends ConsumerState<BuyerMapScreen> {
  GoogleMapController? _controller;
  String? _selectedId;
  bool _openOnly = false;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _select(PublicWarung warung) {
    setState(() => _selectedId = warung.id);
    _controller?.animateCamera(
      CameraUpdate.newLatLng(LatLng(warung.lat, warung.lng)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final position = ref.watch(buyerLocationProvider).value;
    final nearby = ref.watch(nearbyWarungsProvider);
    final warungs = (nearby.value ?? const <PublicWarung>[])
        .where((warung) => !_openOnly || isOpenAt(warung.hours, now))
        .toList();
    final selected =
        warungs.where((w) => w.id == _selectedId).firstOrNull ??
        warungs.firstOrNull;
    final origin = position ?? fallbackCoordinates;
    final within1Km = warungs.where((w) => (w.distance ?? 0) <= 1000).length;

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(origin.lat, origin.lng),
              zoom: 15,
            ),
            onMapCreated: (controller) => _controller = controller,
            myLocationEnabled: position != null,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            // Keeps the Google logo clear of the card at the bottom.
            padding: const EdgeInsets.only(bottom: 220, top: 120),
            markers: {
              for (final warung in warungs)
                Marker(
                  markerId: MarkerId(warung.id),
                  position: LatLng(warung.lat, warung.lng),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    warung.id == selected?.id
                        ? BitmapDescriptor.hueYellow
                        : 150,
                  ),
                  zIndexInt: warung.id == selected?.id ? 1 : 0,
                  onTap: () => _select(warung),
                ),
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Material(
                    color: AppColors.white,
                    elevation: 2,
                    shadowColor: Colors.black26,
                    borderRadius: BorderRadius.circular(14),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => context.go(Routes.buyerSearch),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              LucideIcons.search,
                              color: AppColors.inkMuted,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Cari barang, misalnya Indomie',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: AppColors.inkMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilterChip(
                    label: const Text('Buka sekarang'),
                    selected: _openOnly,
                    onSelected: (value) => setState(() => _openOnly = value),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _Sheet(
              loading: !nearby.hasValue && !nearby.hasError,
              failed: nearby.hasError,
              located: position != null,
              count: within1Km,
              warung: selected,
              now: now,
              onRetry: () => ref.invalidate(nearbyWarungsProvider),
            ),
          ),
        ],
      ),
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.loading,
    required this.failed,
    required this.located,
    required this.count,
    required this.warung,
    required this.now,
    required this.onRetry,
  });

  final bool loading;
  final bool failed;
  final bool located;
  final int count;
  final PublicWarung? warung;
  final DateTime now;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warung = this.warung;

    final Widget content;
    if (loading) {
      content = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (failed) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Gagal memuat warung. Cek internet, lalu coba lagi.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Coba lagi')),
        ],
      );
    } else if (warung == null) {
      content = Text(
        'Belum ada warung di sekitar sini yang tampil di peta.',
        style: theme.textTheme.bodyLarge,
      );
    } else {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            located
                ? '$count warung dalam 1 km'
                : 'Lokasi belum aktif, menampilkan sekitar Telang',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Text(warung.name, style: theme.textTheme.headlineSmall),
          Text(
            located
                ? '${describeWarung(warung, now)} dari lokasimu'
                : describeWarung(warung, now).split(', ').last,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const CircleAvatar(radius: 4, backgroundColor: AppColors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  describeFreshness(warung, now),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: FilledButton(
                  onPressed: () => context.push(
                    Routes.buyerWarung(warung.id),
                    extra: warung,
                  ),
                  child: const Text('Lihat barang'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: () => openDirections(warung),
                  icon: const Icon(LucideIcons.navigation),
                  label: Text(
                    'Arah',
                    style: AppText.body(
                      16,
                      weight: FontWeight.w600,
                      color: AppColors.green,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Material(
      color: AppColors.cream,
      elevation: 8,
      shadowColor: Colors.black38,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: SizedBox(width: double.infinity, child: content),
        ),
      ),
    );
  }
}
