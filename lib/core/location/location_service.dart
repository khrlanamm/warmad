import 'package:geolocator/geolocator.dart';

typedef Coordinates = ({double lat, double lng});

/// Why the device position could not be read.
enum LocationIssue {
  /// Location (GPS) is switched off on the phone.
  serviceOff,

  /// The user has not granted the permission yet, or declined it once.
  denied,

  /// The user declined for good. Only the app settings can change it.
  deniedForever,

  /// Permission is fine but no position came back in time.
  unavailable,
}

/// The device position, or the reason there is none.
typedef LocationFix = ({Coordinates? coordinates, LocationIssue? issue});

/// Reads the device position, asking for permission when needed.
Future<LocationFix> locate() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return (coordinates: null, issue: LocationIssue.serviceOff);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      return (coordinates: null, issue: LocationIssue.denied);
    }
    if (permission == LocationPermission.deniedForever) {
      return (coordinates: null, issue: LocationIssue.deniedForever);
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
    return (
      coordinates: (lat: position.latitude, lng: position.longitude),
      issue: null,
    );
  } catch (_) {
    return (coordinates: null, issue: LocationIssue.unavailable);
  }
}

/// Returns the device position, asking for permission when needed.
/// Returns null when location is off, denied, or cannot be read in time.
Future<Coordinates?> currentCoordinates() async => (await locate()).coordinates;
