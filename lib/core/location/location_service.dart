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
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );
    return (lat: position.latitude, lng: position.longitude);
  } catch (_) {
    return null;
  }
}
