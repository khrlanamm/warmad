import 'dart:math' as math;

const _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

/// Encodes a coordinate as a geohash. Nearby places share a prefix, which
/// turns "warungs near me" into a range query. Same algorithm as
/// functions/src/geo.ts, which stamps the hash on each warung.
String encodeGeohash(double lat, double lng, {int precision = 9}) {
  var latMin = -90.0, latMax = 90.0;
  var lngMin = -180.0, lngMax = 180.0;
  final hash = StringBuffer();
  var bits = 0, value = 0;
  var evenBit = true;

  while (hash.length < precision) {
    if (evenBit) {
      final mid = (lngMin + lngMax) / 2;
      if (lng >= mid) {
        value = (value << 1) | 1;
        lngMin = mid;
      } else {
        value = value << 1;
        lngMax = mid;
      }
    } else {
      final mid = (latMin + latMax) / 2;
      if (lat >= mid) {
        value = (value << 1) | 1;
        latMin = mid;
      } else {
        value = value << 1;
        latMax = mid;
      }
    }
    evenBit = !evenBit;
    if (++bits == 5) {
      hash.write(_base32[value]);
      bits = 0;
      value = 0;
    }
  }
  return hash.toString();
}

/// Geohash cells to search for places around a point: the cell the point is
/// in and its eight neighbours, as 5-character prefixes. One cell is about
/// 4.9 km on a side, so together they cover roughly 15 by 15 km and never
/// miss a place just across a cell border.
Set<String> nearbyGeohashCells(double lat, double lng) {
  // Size of a 5-character cell in degrees.
  const latStep = 180 / 4096;
  const lngStep = 360 / 8192;
  return {
    for (final dLat in const [-1, 0, 1])
      for (final dLng in const [-1, 0, 1])
        encodeGeohash(
          (lat + dLat * latStep).clamp(-90.0, 90.0),
          lng + dLng * lngStep,
          precision: 5,
        ),
  };
}

/// Distance between two coordinates in metres, along the Earth's surface.
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthRadius = 6371000.0;
  double radians(double degrees) => degrees * math.pi / 180;
  final dLat = radians(lat2 - lat1);
  final dLng = radians(lng2 - lng1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(radians(lat1)) *
          math.cos(radians(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return 2 * earthRadius * math.asin(math.min(1, math.sqrt(a)));
}

/// "250 m" below a kilometre, rounded to the nearest 10 m; "1,2 km" above.
String formatDistance(double meters) {
  if (meters < 995) return '${(meters / 10).round() * 10} m';
  final tenths = (meters / 100).round();
  return tenths % 10 == 0
      ? '${tenths ~/ 10} km'
      : '${tenths ~/ 10},${tenths % 10} km';
}
