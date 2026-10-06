import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../auth/data/auth_service.dart';
import '../../profile/data/profile_repository.dart';
import '../domain/cash_state.dart';
import '../domain/warung.dart';

final warungRepositoryProvider = Provider<WarungRepository>(
  (ref) => WarungRepository(
    ref.watch(firestoreProvider),
    ref.watch(functionsProvider),
  ),
);

/// The warung of the signed in member, or null when there is none.
final currentWarungProvider = StreamProvider<Warung?>((ref) {
  final membership = ref.watch(membershipProvider.select((m) => m.value));
  if (membership == null) return Stream.value(null);
  return ref.watch(warungRepositoryProvider).watchWarung(membership.warungId);
});

/// Counters of the open cash period of the current warung.
final cashStateProvider = StreamProvider<CashState?>((ref) {
  final membership = ref.watch(membershipProvider.select((m) => m.value));
  if (membership == null) return Stream.value(null);
  return ref.watch(warungRepositoryProvider).watchCash(membership.warungId);
});

class WarungRepository {
  WarungRepository(this._db, this._functions);

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  DocumentReference<Map<String, dynamic>> _warung(String id) =>
      _db.doc('warungs/$id');

  Stream<Warung?> watchWarung(String id) =>
      _warung(id)
          .snapshots()
          .map((s) => s.exists ? Warung.fromSnapshot(s) : null);

  Stream<CashState?> watchCash(String id) =>
      _warung(id).collection('cash').doc('current').snapshots().map((s) {
        final data = s.data();
        if (data == null) return null;
        return CashState.fromMap(
          data,
          openedAt: (data['openedAt'] as Timestamp?)?.toDate(),
        );
      });

  /// Registers a warung and makes the caller its owner. Needs a connection:
  /// the server grants the claims that unlock the warung data.
  Future<void> create(NewWarung warung, AuthService auth) async {
    await _functions.httpsCallable('createWarung').call<void>(warung.toMap());
    // Pick up the new `wid` and `role` claims right away.
    await auth.currentUser?.getIdToken(true);
  }

  Future<void> setShowOnMap(String id, bool value) {
    return settleWrite(
      _warung(
        id,
      ).update({'showOnMap': value, 'updatedAt': FieldValue.serverTimestamp()}),
    );
  }
}
