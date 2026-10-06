import 'package:cloud_firestore/cloud_firestore.dart';

class OpeningHours {
  const OpeningHours.allDay() : is24h = true, open = null, close = null;
  const OpeningHours.custom({
    required String this.open,
    required String this.close,
  }) : is24h = false;

  factory OpeningHours.fromMap(Map<String, dynamic>? map) {
    final open = map?['open'] as String?;
    final close = map?['close'] as String?;
    if (map?['is24h'] == false && open != null && close != null) {
      return OpeningHours.custom(open: open, close: close);
    }
    return const OpeningHours.allDay();
  }

  final bool is24h;

  /// "HH:mm", null when open 24 hours.
  final String? open;
  final String? close;

  Map<String, dynamic> toMap() =>
      is24h ? {'is24h': true} : {'is24h': false, 'open': open, 'close': close};

  String get label => is24h ? '24 jam' : '$open–$close';
}

/// The private `warungs/{id}` document. Only members can read it.
class Warung {
  const Warung({
    required this.id,
    required this.name,
    required this.phone,
    required this.address,
    required this.lat,
    required this.lng,
    required this.hours,
    required this.showOnMap,
    required this.ownerUid,
    this.cashReminderTime,
  });

  factory Warung.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? const {};
    final location = data['location'] as GeoPoint?;
    return Warung(
      id: snapshot.id,
      name: data['name'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      address: data['address'] as String? ?? '',
      lat: location?.latitude ?? 0,
      lng: location?.longitude ?? 0,
      hours: OpeningHours.fromMap(data['hours'] as Map<String, dynamic>?),
      showOnMap: data['showOnMap'] as bool? ?? false,
      ownerUid: data['ownerUid'] as String? ?? '',
      cashReminderTime: data['cashReminderTime'] as String?,
    );
  }

  final String id;
  final String name;
  final String phone;
  final String address;
  final double lat;
  final double lng;
  final OpeningHours hours;

  /// Whether buyers can see this warung on the map. Off unless the owner
  /// turns it on.
  final bool showOnMap;
  final String ownerUid;

  /// "HH:mm" of the daily cash closing reminder, null when off.
  final String? cashReminderTime;
}

/// What the owner fills in to register a warung.
class NewWarung {
  const NewWarung({
    required this.name,
    required this.phone,
    required this.address,
    required this.lat,
    required this.lng,
    required this.hours,
    required this.showOnMap,
    required this.openingBalance,
  });

  final String name;
  final String phone;
  final String address;
  final double lat;
  final double lng;
  final OpeningHours hours;
  final bool showOnMap;

  /// Cash in the drawer right now, in Rupiah.
  final int openingBalance;

  Map<String, dynamic> toMap() => {
    'name': name,
    'phone': phone,
    'address': address,
    'lat': lat,
    'lng': lng,
    'hours': hours.toMap(),
    'showOnMap': showOnMap,
    'openingBalance': openingBalance,
  };
}
