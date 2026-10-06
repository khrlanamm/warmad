import '../../warung/domain/warung.dart';

/// What a buyer may know about a product at a warung. Never a stock count.
enum Availability {
  tersedia,
  terbatas,
  habis;

  static Availability parse(Object? value) =>
      Availability.values.where((a) => a.name == value).firstOrNull ??
      Availability.habis;

  String get label => switch (this) {
    tersedia => 'Tersedia',
    terbatas => 'Terbatas',
    habis => 'Habis',
  };
}

/// A product as buyers see it (`publicWarungs/{id}/items/{catalogId}`).
class PublicItem {
  const PublicItem({
    required this.catalogId,
    required this.name,
    required this.status,
    this.category,
  });

  factory PublicItem.fromMap(String catalogId, Map<String, dynamic> data) =>
      PublicItem(
        catalogId: catalogId,
        name: data['name'] as String? ?? '',
        status: Availability.parse(data['status']),
        category: data['category'] as String?,
      );

  final String catalogId;
  final String name;
  final Availability status;
  final String? category;
}

/// A warung as buyers see it (`publicWarungs/{id}`). It exists only when the
/// owner chose to appear on the map.
class PublicWarung {
  const PublicWarung({
    required this.id,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    required this.hours,
    this.lastActiveAt,
    this.distance,
  });

  final String id;
  final String name;
  final String address;
  final double lat;
  final double lng;
  final OpeningHours hours;

  /// When the warung last recorded a sale or a stock change. Availability is
  /// only as fresh as this.
  final DateTime? lastActiveAt;

  /// Metres from the buyer, when the buyer's position is known.
  final double? distance;

  PublicWarung withDistance(double meters) => PublicWarung(
    id: id,
    name: name,
    address: address,
    lat: lat,
    lng: lng,
    hours: hours,
    lastActiveAt: lastActiveAt,
    distance: meters,
  );
}

/// Whether a warung with [hours] is open at [now].
///
/// Handles hours that run past midnight, for example 16:00 to 02:00.
bool isOpenAt(OpeningHours hours, DateTime now) {
  if (hours.is24h) return true;
  int? minutes(String? time) {
    final parts = time?.split(':');
    if (parts == null || parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    return hour == null || minute == null ? null : hour * 60 + minute;
  }

  final open = minutes(hours.open);
  final close = minutes(hours.close);
  // Unreadable hours: do not claim the warung is closed.
  if (open == null || close == null || open == close) return true;
  final current = now.hour * 60 + now.minute;
  return open < close
      ? current >= open && current < close
      : current >= open || current < close;
}
