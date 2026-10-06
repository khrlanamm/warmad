import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/location/location_service.dart';

/// Map with a fixed pin in the middle. The owner drags the map until the pin
/// sits on the warung; the map center is the chosen location.
class LocationPicker extends StatefulWidget {
  const LocationPicker({super.key, required this.onChanged});

  /// Called with the map center once the device position is known and every
  /// time the owner stops dragging.
  final ValueChanged<Coordinates> onChanged;

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  // Jl. Telang Raya, Kamal, Bangkalan. Used until the device position is known.
  static const _fallback = LatLng(-7.1289, 112.7243);

  GoogleMapController? _controller;
  LatLng _center = _fallback;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _useMyLocation();
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    final position = await currentCoordinates();
    if (!mounted) return;
    setState(() => _locating = false);
    if (position == null) return;

    _center = LatLng(position.lat, position.lng);
    widget.onChanged(position);
    await _controller?.animateCamera(CameraUpdate.newLatLngZoom(_center, 17));
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 200,
        child: Stack(
          alignment: Alignment.center,
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(target: _center, zoom: 16),
              onMapCreated: (controller) {
                _controller = controller;
                if (_center != _fallback) {
                  controller.moveCamera(
                    CameraUpdate.newLatLngZoom(_center, 17),
                  );
                }
              },
              onCameraMove: (position) => _center = position.target,
              onCameraIdle: () => widget.onChanged((
                lat: _center.latitude,
                lng: _center.longitude,
              )),
              // The picker sits inside a scrolling form, so it must claim
              // drags before the scroll view does.
              gestureRecognizers: {
                Factory<OneSequenceGestureRecognizer>(
                  () => EagerGestureRecognizer(),
                ),
              },
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: false,
            ),
            // Lift the pin so its tip, not its middle, marks the center.
            const IgnorePointer(
              child: Padding(
                padding: EdgeInsets.only(bottom: 36),
                child: Icon(
                  Icons.location_on,
                  size: 40,
                  color: AppColors.green,
                ),
              ),
            ),
            Positioned(
              bottom: 10,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: const ShapeDecoration(
                    color: AppColors.white,
                    shape: StadiumBorder(),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Text(
                      'Geser peta sampai pin di lokasi warung',
                      style: AppText.body(13, weight: FontWeight.w500),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.white,
                  foregroundColor: AppColors.green,
                ),
                tooltip: 'Pakai lokasi saya',
                onPressed: _locating ? null : _useMyLocation,
                icon: _locating
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.locateFixed),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
