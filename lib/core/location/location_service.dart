import 'package:geolocator/geolocator.dart';

typedef Coordinates = ({double lat, double lng});

/// Returns the device position, asking for permission when needed.
/// Returns null when location is off, denied, or cannot be read in time.
Future<Coordinates?> currentCoordinates() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    final position = await Geolocator.getCurrentPosition(
      // The platform location manager is used instead of Google's fused
      // provider. The fused provider insists on a second dialog asking the
      // user to turn on Google Location Accuracy, and returns nothing when
      // that is declined.
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
        forceLocationManager: true,
      ),
    );
    return (lat: position.latitude, lng: position.longitude);
  } catch (_) {
    return null;
  }
}
