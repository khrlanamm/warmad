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

/// Search radii a buyer can pick, in kilometres.
const radiusOptionsKm = [1, 3, 5, 10, 20];

/// The smallest search radius that reaches a place [meters] away, or null
/// when it is beyond the largest one.
int? radiusCovering(double meters) =>
    radiusOptionsKm.where((km) => km * 1000 >= meters).firstOrNull;

/// Geohash cells, as prefixes, that together cover every place within
/// [radiusMeters] of a point.
///
/// Up to 5 km the cells have 5 characters (about 4.9 km on a side), so at
/// most 16 are needed. Larger radii use 4-character cells (about 39 by
/// 19.5 km), at most 12 for 20 km. Each cell is one range query.
Set<String> geohashCellsCovering(double lat, double lng, double radiusMeters) {
  final precision = radiusMeters <= 5000 ? 5 : 4;
  // Size of one cell in degrees: 5 characters hold 13 longitude bits and 12
  // latitude bits, 4 characters hold 10 of each.
  final latStep = precision == 5 ? 180 / 4096 : 180 / 1024;
  final lngStep = precision == 5 ? 360 / 8192 : 360 / 1024;

  const metersPerDegree = 111320.0;
  final dLat = radiusMeters / metersPerDegree;
  final dLng =
      radiusMeters /
      (metersPerDegree * math.max(math.cos(lat * math.pi / 180), 0.01));
  final south = (lat - dLat).clamp(-90.0, 90.0);
  final north = (lat + dLat).clamp(-90.0, 90.0);
  final west = lng - dLng;
  final east = lng + dLng;

  // Steps the size of one cell, plus the far edge, land in every cell the
  // box touches.
  List<double> samples(double from, double to, double step) => [
    for (var value = from; value < to; value += step) value,
    to,
  ];

  return {
    for (final sampleLat in samples(south, north, latStep))
      for (final sampleLng in samples(west, east, lngStep))
        encodeGeohash(
          sampleLat,
          (sampleLng + 540) % 360 - 180,
          precision: precision,
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
