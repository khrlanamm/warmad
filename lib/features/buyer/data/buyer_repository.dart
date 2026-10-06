import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/location/location_service.dart';
import '../../warung/domain/warung.dart';
import '../domain/geo.dart';
import '../domain/public_warung.dart';

final buyerRepositoryProvider = Provider<BuyerRepository>(
  (ref) => BuyerRepository(ref.watch(firestoreProvider)),
);

/// Jl. Telang Raya, Kamal. Used when the buyer's position is not available.
const fallbackCoordinates = (lat: -7.1289, lng: 112.7243);

/// The buyer's position, or null when location is off or denied.
final buyerLocationProvider = FutureProvider<Coordinates?>(
  (ref) => currentCoordinates(),
);

/// Warungs around the buyer, nearest first.
final nearbyWarungsProvider = FutureProvider<List<PublicWarung>>((ref) async {
  final position = await ref.watch(buyerLocationProvider.future);
  final origin = position ?? fallbackCoordinates;
  return ref.watch(buyerRepositoryProvider).nearby(origin.lat, origin.lng);
});

/// Goods of one warung as buyers see them, by name.
final publicItemsProvider = FutureProvider.autoDispose
    .family<List<PublicItem>, String>(
      (ref, warungId) => ref.watch(buyerRepositoryProvider).items(warungId),
    );

/// Reads only the public copies. Buyers have no access to a warung's own
/// documents, so nothing here can reveal stock counts, prices or cash.
class BuyerRepository {
  BuyerRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _warungs =>
      _db.collection('publicWarungs');

  static PublicWarung _warungOf(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const {};
    final location = data['location'] as GeoPoint?;
    return PublicWarung(
      id: snapshot.id,
      name: data['name'] as String? ?? '',
      address: data['address'] as String? ?? '',
      lat: location?.latitude ?? 0,
      lng: location?.longitude ?? 0,
      hours: OpeningHours.fromMap(data['hours'] as Map<String, dynamic>?),
      lastActiveAt: (data['lastActiveAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Warungs within roughly 7 km of a point, nearest first.
  ///
  /// One small range query per geohash cell around the point. Only warungs
  /// in those cells are read, however many exist elsewhere.
  Future<List<PublicWarung>> nearby(double lat, double lng) async {
    final snapshots = await Future.wait([
      for (final cell in nearbyGeohashCells(lat, lng))
        _warungs.orderBy('geohash').startAt([cell]).endAt(['$cell']).get(),
    ]);
    final found = <String, PublicWarung>{};
    for (final snapshot in snapshots) {
      for (final doc in snapshot.docs) {
        final warung = _warungOf(doc);
        found[warung.id] = warung.withDistance(
          distanceMeters(lat, lng, warung.lat, warung.lng),
        );
      }
    }
    return found.values.toList()
      ..sort((a, b) => a.distance!.compareTo(b.distance!));
  }

  /// How one catalog item stands at each of [warungs]. Warungs that do not
  /// sell it are left out. One document read per warung.
  Future<Map<String, PublicItem>> availability(
    String catalogId,
    List<PublicWarung> warungs,
  ) async {
    final snapshots = await Future.wait([
      for (final warung in warungs)
        _warungs.doc(warung.id).collection('items').doc(catalogId).get(),
    ]);
    return {
      for (final (index, snapshot) in snapshots.indexed)
        if (snapshot.exists)
          warungs[index].id: PublicItem.fromMap(catalogId, snapshot.data()!),
    };
  }

  Future<List<PublicItem>> items(String warungId) async {
    final snapshot = await _warungs
        .doc(warungId)
        .collection('items')
        .orderBy('name')
        .get();
    return [
      for (final doc in snapshot.docs) PublicItem.fromMap(doc.id, doc.data()),
    ];
  }
}
