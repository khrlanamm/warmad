import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/location/location_service.dart';
import '../data/buyer_repository.dart';
import '../domain/geo.dart';
import '../domain/public_warung.dart';
import 'buyer_widgets.dart';

/// Peta: warungs around the buyer, on a map or as a list.
class BuyerMapScreen extends ConsumerStatefulWidget {
  const BuyerMapScreen({super.key});

  @override
  ConsumerState<BuyerMapScreen> createState() => _BuyerMapScreenState();
}

class _BuyerMapScreenState extends ConsumerState<BuyerMapScreen> {
  GoogleMapController? _controller;
  late final AppLifecycleListener _lifecycle;
  String? _selectedId;
  bool _openOnly = false;
  bool _showList = false;

  // Whether the camera should keep framing the search circle. Turns off
  // once the buyer moves the map or uses the buttons.
  bool _autoFit = true;

  // Sizes of what covers the map, so the camera centres the radius in the
  // part that stays visible. Measured after layout.
  Size _viewport = Size.zero;
  double _headerHeight = 150;
  double _sheetHeight = 220;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _controller?.dispose();
    super.dispose();
  }

  /// Back from the phone settings: GPS or the permission may be on now.
  void _onResume() {
    final issue = ref.read(buyerLocationProvider).value?.issue;
    if (issue == LocationIssue.serviceOff ||
        issue == LocationIssue.deniedForever) {
      ref.invalidate(buyerLocationProvider);
    }
  }

  /// Takes the buyer to whatever clears [issue].
  void _fixLocation(LocationIssue? issue) {
    switch (issue) {
      case LocationIssue.serviceOff:
        Geolocator.openLocationSettings();
      case LocationIssue.deniedForever:
        Geolocator.openAppSettings();
      case LocationIssue.denied || LocationIssue.unavailable || null:
        ref.invalidate(buyerLocationProvider);
    }
  }

  Coordinates get _origin =>
      ref.read(buyerLocationProvider).value?.coordinates ?? fallbackCoordinates;

  /// Zoom at which a circle of [meters] fits the visible part of the map.
  double _zoomToFit(double lat, double meters) {
    final width = _viewport.width - 48;
    // The card is short while loading and grows once warungs arrive, so
    // the zoom allows for its usual height.
    final sheet = math.max(_sheetHeight, 230.0);
    final height = _viewport.height - _headerHeight - sheet - 48;
    final pixels = math.max(math.min(width, height), 120.0);
    // At zoom 0 one logical pixel covers 156543 m at the equator, half as
    // much with every zoom level.
    final metersPerPixel = 2 * meters / pixels;
    final zoom =
        math.log(156543.03 * math.cos(lat * math.pi / 180) / metersPerPixel) /
        math.ln2;
    return zoom.clamp(3.0, 18.0);
  }

  /// Frames the search circle around the buyer.
  void _fitRadius({bool animate = true}) {
    final controller = _controller;
    if (!mounted || !_autoFit || controller == null || _viewport == Size.zero) {
      return;
    }
    final origin = _origin;
    final update = CameraUpdate.newLatLngZoom(
      LatLng(origin.lat, origin.lng),
      _zoomToFit(origin.lat, ref.read(buyerRadiusProvider) * 1000.0),
    );
    animate ? controller.animateCamera(update) : controller.moveCamera(update);
  }

  Future<void> _recenter() async {
    final fix = ref.read(buyerLocationProvider).value;
    final position = fix?.coordinates;
    if (position == null) {
      // Still looking for the position: nothing to do yet.
      if (fix != null) _fixLocation(fix.issue);
      return;
    }
    _autoFit = false;
    _controller?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(position.lat, position.lng), 16),
    );

    // The buyer may have moved on since the position was read. Only a real
    // move reads the warungs again.
    final fresh = await currentCoordinates();
    if (!mounted || fresh == null) return;
    final moved = distanceMeters(
      position.lat,
      position.lng,
      fresh.lat,
      fresh.lng,
    );
    if (moved > 200) ref.invalidate(buyerLocationProvider);
  }

  void _zoom(CameraUpdate update) {
    _autoFit = false;
    _controller?.animateCamera(update);
  }

  /// The header or the card changed height, which moves the visible part
  /// of the map.
  void _coverChanged({double? header, double? sheet}) {
    if (!mounted) return;
    if ((header ?? _headerHeight) == _headerHeight &&
        (sheet ?? _sheetHeight) == _sheetHeight) {
      return;
    }
    setState(() {
      _headerHeight = header ?? _headerHeight;
      _sheetHeight = sheet ?? _sheetHeight;
    });
    // The map takes the new padding a moment after the rebuild. A camera
    // move sent before that would still centre on the old padding.
    Future<void>.delayed(const Duration(milliseconds: 100), _fitRadius);
  }

  void _select(PublicWarung warung) {
    setState(() => _selectedId = warung.id);
    _autoFit = false;
    _controller?.animateCamera(
      CameraUpdate.newLatLng(LatLng(warung.lat, warung.lng)),
    );
  }

  void _setRadius(int km) => ref.read(buyerRadiusProvider.notifier).set(km);

  @override
  Widget build(BuildContext context) {
    ref.listen(buyerLocationProvider, (previous, next) {
      if (!next.hasValue) return;
      _autoFit = true;
      _fitRadius();
    });
    ref.listen(buyerRadiusProvider, (previous, next) {
      _autoFit = true;
      _fitRadius();
    });

    final now = DateTime.now();
    final fix = ref.watch(buyerLocationProvider);
    final position = fix.value?.coordinates;
    final located = position != null;
    final origin = position ?? fallbackCoordinates;
    final radiusKm = ref.watch(buyerRadiusProvider);
    final nearby = ref.watch(nearbyWarungsProvider);
    final all = nearby.value ?? const <PublicWarung>[];
    final warungs = all
        .where((warung) => !_openOnly || isOpenAt(warung.hours, now))
        .toList();
    final selected =
        warungs.where((w) => w.id == _selectedId).firstOrNull ??
        warungs.firstOrNull;

    // With nothing in the radius, look further out to say how far the
    // nearest warung is.
    final maxKm = radiusOptionsKm.last;
    final wider = nearby.hasValue && !nearby.isLoading && all.isEmpty
        ? (radiusKm == maxKm ? nearby : ref.watch(warungsWithinProvider(maxKm)))
        : null;

    final status = _NearbyStatus(
      locating: fix.isLoading,
      loading: nearby.isLoading,
      failed: nearby.hasError && !nearby.isLoading,
      located: located,
      radiusKm: radiusKm,
      all: all,
      warungs: warungs,
      openOnly: _openOnly,
      wider: wider,
      now: now,
      onRetry: () => ref.invalidate(nearbyWarungsProvider),
      onExpand: _setRadius,
      onShowAll: () => setState(() => _openOnly = false),
    );

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = constraints.biggest;
          if (viewport != _viewport) {
            // For example the keyboard from the search tab closing.
            final resized = _viewport != Size.zero;
            _viewport = viewport;
            if (resized) {
              Future<void>.delayed(
                const Duration(milliseconds: 100),
                _fitRadius,
              );
            }
          }
          return Stack(
            children: [
              Listener(
                onPointerDown: (_) => _autoFit = false,
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(origin.lat, origin.lng),
                    zoom: 13,
                  ),
                  onMapCreated: (controller) {
                    _controller = controller;
                    _fitRadius(animate: false);
                  },
                  myLocationEnabled: located,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  compassEnabled: false,
                  // Keeps the Google logo and the camera centre clear of the
                  // header and the card at the bottom.
                  padding: EdgeInsets.only(
                    top: _headerHeight,
                    bottom: _sheetHeight,
                  ),
                  circles: {
                    Circle(
                      circleId: const CircleId('radius'),
                      center: LatLng(origin.lat, origin.lng),
                      radius: radiusKm * 1000.0,
                      fillColor: AppColors.green.withValues(alpha: 0.07),
                      strokeColor: AppColors.green.withValues(alpha: 0.6),
                      strokeWidth: 2,
                    ),
                  },
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
                        infoWindow: InfoWindow(title: warung.name),
                        onTap: () => _select(warung),
                      ),
                  },
                ),
              ),
              if (_showList)
                Positioned.fill(
                  child: ColoredBox(
                    color: AppColors.cream,
                    child: _WarungList(
                      status: status,
                      topInset: _headerHeight,
                      onRefresh: () async {
                        ref.invalidate(buyerLocationProvider);
                        await ref.read(nearbyWarungsProvider.future);
                      },
                    ),
                  ),
                ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _MeasureSize(
                  onChange: (size) => _coverChanged(header: size.height),
                  child: _Header(
                    background: _showList ? AppColors.cream : null,
                    openOnly: _openOnly,
                    onOpenOnly: (value) => setState(() => _openOnly = value),
                    showList: _showList,
                    onShowList: (value) => setState(() => _showList = value),
                    issue: fix.isLoading ? null : fix.value?.issue,
                    onFixLocation: () => _fixLocation(fix.value?.issue),
                  ),
                ),
              ),
              if (!_showList)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 0, 16, 12),
                        child: _MapControls(
                          onRecenter: _recenter,
                          onZoomIn: () => _zoom(CameraUpdate.zoomIn()),
                          onZoomOut: () => _zoom(CameraUpdate.zoomOut()),
                        ),
                      ),
                      _MeasureSize(
                        onChange: (size) => _coverChanged(sheet: size.height),
                        child: _Sheet(
                          status: status,
                          warung: selected,
                          onShowList: () => setState(() => _showList = true),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Everything the sheet and the list need to say how the search went.
class _NearbyStatus {
  const _NearbyStatus({
    required this.locating,
    required this.loading,
    required this.failed,
    required this.located,
    required this.radiusKm,
    required this.all,
    required this.warungs,
    required this.openOnly,
    required this.wider,
    required this.now,
    required this.onRetry,
    required this.onExpand,
    required this.onShowAll,
  });

  final bool locating;
  final bool loading;
  final bool failed;
  final bool located;
  final int radiusKm;

  /// Every warung in the radius, nearest first.
  final List<PublicWarung> all;

  /// The warungs left after the "Buka sekarang" filter.
  final List<PublicWarung> warungs;
  final bool openOnly;

  /// Warungs within the largest radius, read only when [all] is empty.
  final AsyncValue<List<PublicWarung>>? wider;
  final DateTime now;
  final VoidCallback onRetry;
  final ValueChanged<int> onExpand;
  final VoidCallback onShowAll;

  String get summary =>
      describeNearby(warungs, radiusKm, located: located, openOnly: openOnly);

  /// What to show instead of warungs, or null when there are some.
  Widget? placeholder(BuildContext context) {
    final theme = Theme.of(context);
    if (locating || loading) {
      return _Busy(locating ? 'Mencari lokasimu…' : 'Memuat warung…');
    }
    if (failed) {
      return Column(
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
    }
    if (all.isEmpty) return _NearbyEmpty(status: this);
    if (warungs.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            all.length == 1
                ? 'Satu-satunya warung dalam $radiusKm km sedang tutup.'
                : 'Semua ${all.length} warung dalam $radiusKm km sedang '
                      'tutup.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onShowAll,
            child: const Text('Tampilkan semua'),
          ),
        ],
      );
    }
    return null;
  }
}

class _Busy extends StatelessWidget {
  const _Busy(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(width: 12),
          Text(label, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

/// No warung in the radius: say so plainly, and how far the nearest is.
class _NearbyEmpty extends StatelessWidget {
  const _NearbyEmpty({required this.status});

  final _NearbyStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radiusKm = status.radiusKm;
    final maxKm = radiusOptionsKm.last;
    final from = status.located ? 'lokasimu' : fallbackPlaceName;
    final wider = status.wider;
    final nearest = wider?.value?.firstOrNull;
    final expandTo = nearest == null ? null : radiusCovering(nearest.distance!);

    final Widget detail;
    if (wider == null || wider.isLoading) {
      detail = Text(
        'Mencari warung terdekat…',
        style: theme.textTheme.bodyMedium,
      );
    } else if (nearest != null && expandTo != null) {
      detail = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Warung terdekat: '),
                TextSpan(
                  text: nearest.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text:
                      ', ${formatDistance(nearest.distance!)} dari '
                      '$from.',
                ),
              ],
            ),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => status.onExpand(expandTo),
            child: Text('Perluas ke $expandTo km'),
          ),
        ],
      );
    } else if (wider.hasError) {
      detail = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Coba perluas jarak pencarian.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => status.onExpand(maxKm),
            child: Text('Perluas ke $maxKm km'),
          ),
        ],
      );
    } else {
      detail = Text(
        radiusKm == maxKm
            ? 'Warmad belum dipakai warung di sekitar $from. Coba lagi lain '
                  'waktu.'
            : 'Sampai $maxKm km dari $from pun belum ada warung yang '
                  'memakai Warmad.',
        style: theme.textTheme.bodyMedium,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.yellowTint,
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
              child: Padding(
                padding: EdgeInsets.all(10),
                child: Icon(LucideIcons.mapPinOff, color: AppColors.yellowDark),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Tidak ada warung Madura dalam radius $radiusKm km',
                style: theme.textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        detail,
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.background,
    required this.openOnly,
    required this.onOpenOnly,
    required this.showList,
    required this.onShowList,
    required this.issue,
    required this.onFixLocation,
  });

  final Color? background;
  final bool openOnly;
  final ValueChanged<bool> onOpenOnly;
  final bool showList;
  final ValueChanged<bool> onShowList;
  final LocationIssue? issue;
  final VoidCallback onFixLocation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final issue = this.issue;

    return ColoredBox(
      color: background ?? Colors.transparent,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        Expanded(
                          child: Text(
                            'Cari barang, misalnya Indomie',
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: AppColors.inkMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          const RadiusChip(),
                          const SizedBox(width: 8),
                          FilterChip(
                            label: const Text('Buka sekarang'),
                            selected: openOnly,
                            onSelected: onOpenOnly,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: const [
                      ButtonSegment(
                        value: false,
                        icon: Icon(LucideIcons.map, size: 18),
                        tooltip: 'Tampilkan peta',
                      ),
                      ButtonSegment(
                        value: true,
                        icon: Icon(LucideIcons.list, size: 18),
                        tooltip: 'Tampilkan daftar',
                      ),
                    ],
                    selected: {showList},
                    onSelectionChanged: (value) => onShowList(value.first),
                  ),
                ],
              ),
              if (issue != null) ...[
                const SizedBox(height: 8),
                _LocationBanner(issue: issue, onAction: onFixLocation),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Says why the buyer's position is missing and offers the way to fix it.
class _LocationBanner extends StatelessWidget {
  const _LocationBanner({required this.issue, required this.onAction});

  final LocationIssue issue;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final (message, action) = switch (issue) {
      LocationIssue.serviceOff => ('GPS mati.', 'Nyalakan'),
      LocationIssue.denied => ('Izin lokasi belum diberikan.', 'Izinkan'),
      LocationIssue.deniedForever => (
        'Izin lokasi ditolak.',
        'Buka pengaturan',
      ),
      LocationIssue.unavailable => ('Lokasimu belum terbaca.', 'Coba lagi'),
    };

    return Material(
      color: AppColors.yellowTint,
      elevation: 2,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: Row(
          children: [
            const Icon(
              LucideIcons.locateOff,
              size: 20,
              color: AppColors.yellowDark,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$message Menampilkan sekitar $fallbackPlaceName.',
                style: AppText.body(13, weight: FontWeight.w500),
              ),
            ),
            TextButton(onPressed: onAction, child: Text(action)),
          ],
        ),
      ),
    );
  }
}

/// My location and zoom buttons, the way most map apps place them.
class _MapControls extends StatelessWidget {
  const _MapControls({
    required this.onRecenter,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final VoidCallback onRecenter;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    Widget panel(Widget child) => Material(
      color: AppColors.white,
      elevation: 3,
      shadowColor: Colors.black38,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
    Widget button(IconData icon, String tooltip, VoidCallback onPressed) =>
        IconButton(
          tooltip: tooltip,
          color: AppColors.green,
          onPressed: onPressed,
          icon: Icon(icon),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        panel(button(LucideIcons.locateFixed, 'Lokasi saya', onRecenter)),
        const SizedBox(height: 10),
        panel(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              button(LucideIcons.plus, 'Perbesar', onZoomIn),
              const SizedBox(width: 28, child: Divider(height: 1)),
              button(LucideIcons.minus, 'Perkecil', onZoomOut),
            ],
          ),
        ),
      ],
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.status,
    required this.warung,
    required this.onShowList,
  });

  final _NearbyStatus status;
  final PublicWarung? warung;
  final VoidCallback onShowList;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warung = this.warung;
    final located = status.located;
    final now = status.now;

    final content =
        status.placeholder(context) ??
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(status.summary, style: theme.textTheme.bodySmall),
                ),
                if (status.warungs.length > 1)
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: onShowList,
                    child: const Text('Lihat daftar'),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(warung!.name, style: theme.textTheme.headlineSmall),
            Text(
              located
                  ? '${formatDistance(warung.distance!)} dari lokasimu · '
                        '${describeHours(warung, now)}'
                  : describeHours(warung, now),
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

/// The same warungs as the map, as a list, nearest first.
class _WarungList extends StatelessWidget {
  const _WarungList({
    required this.status,
    required this.topInset,
    required this.onRefresh,
  });

  final _NearbyStatus status;
  final double topInset;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = status.placeholder(context);

    return RefreshIndicator(
      edgeOffset: topInset,
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, topInset + 4, 16, 20),
        children: [
          if (placeholder != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: placeholder,
              ),
            )
          else ...[
            Text(
              status.summary,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.inkMuted,
              ),
            ),
            const SizedBox(height: 10),
            for (final warung in status.warungs) ...[
              _WarungTile(
                warung: warung,
                located: status.located,
                now: status.now,
              ),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

class _WarungTile extends StatelessWidget {
  const _WarungTile({
    required this.warung,
    required this.located,
    required this.now,
  });

  final PublicWarung warung;
  final bool located;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hours = describeHours(warung, now);

    return Opacity(
      // A closed warung fades back, like a sold-out one in the search.
      opacity: isOpenAt(warung.hours, now) ? 1 : 0.6,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () =>
              context.push(Routes.buyerWarung(warung.id), extra: warung),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
            child: Row(
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.greenTint,
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(LucideIcons.store, color: AppColors.green),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(warung.name, style: theme.textTheme.titleMedium),
                      Text(
                        located
                            ? '${formatDistance(warung.distance!)} · $hours'
                            : hours,
                        style: theme.textTheme.bodyMedium,
                      ),
                      Text(
                        describeFreshness(warung, now),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Arah ke ${warung.name}',
                  color: AppColors.green,
                  onPressed: () => openDirections(warung),
                  icon: const Icon(LucideIcons.navigation),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Reports its child's size after layout, whenever it changes.
class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onChange, required super.child});

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureSize(onChange);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeasureSize renderObject,
  ) => renderObject.onChange = onChange;
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onChange);

  ValueChanged<Size> onChange;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _reported) return;
    _reported = size;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(size));
  }
}
