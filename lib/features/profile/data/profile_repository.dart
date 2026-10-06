import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../auth/data/auth_service.dart';
import '../domain/user_profile.dart';

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(firestoreProvider)),
);

/// UID of the signed in user, or null.
final currentUidProvider = Provider<String?>((ref) {
  ref.watch(authStateProvider); // Rebuild on sign in and sign out.
  return ref.watch(authServiceProvider).currentUser?.uid;
});

// Keyed by UID so that a different account always starts from a clean
// loading state instead of briefly showing the previous account's data.
final profileByUidProvider = StreamProvider.family<UserProfile?, String>(
  (ref, uid) => ref.watch(profileRepositoryProvider).watch(uid),
);

/// The signed in user's profile. Null when signed out or when the user has
/// not picked a role yet.
final userProfileProvider = Provider<AsyncValue<UserProfile?>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return const AsyncData(null);
  return ref.watch(profileByUidProvider(uid));
});

/// Security Rules read the `wid` and `role` claims from the ID token, so the
/// token is the source of truth for membership. The profile document mirrors
/// the claims and tells the app when to fetch a fresh token.
final membershipByUidProvider = FutureProvider.family<Membership?, String>((
  ref,
  uid,
) async {
  final user = ref.watch(authServiceProvider).currentUser;
  if (user == null || user.uid != uid) return null;
  final profile = await ref.watch(profileByUidProvider(uid).future);

  try {
    var claims = (await user.getIdTokenResult()).claims;
    if (claims?['wid'] != profile?.warungId) {
      claims = (await user.getIdTokenResult(true)).claims;
    }
    final warungId = claims?['wid'] as String?;
    final role = WarungRole.parse(claims?['role']);
    if (warungId == null || role == null) return null;
    return Membership(warungId: warungId, role: role);
  } on FirebaseAuthException {
    // Offline with an expired token. Fall back to the cached mirror so the
    // warung can keep working; the rules still check the real claims on sync.
    final warungId = profile?.warungId;
    final role = profile?.role;
    if (warungId == null || role == null) return null;
    return Membership(warungId: warungId, role: role);
  }
});

/// The warung the signed in user belongs to, or null.
final membershipProvider = Provider<AsyncValue<Membership?>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return const AsyncData(null);
  return ref.watch(membershipByUidProvider(uid));
});

class ProfileRepository {
  ProfileRepository(this._db);

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.doc('users/$uid');

  Stream<UserProfile?> watch(String uid) {
    return _doc(uid)
        // Metadata changes are needed to see a cache miss get confirmed by
        // the server; without them that second snapshot is never delivered.
        .snapshots(includeMetadataChanges: true)
        // A miss served from the cache does not mean the profile is absent;
        // wait for the server before treating the user as new.
        .where((s) => s.exists || !s.metadata.isFromCache)
        .map((s) => s.exists ? UserProfile.fromSnapshot(s) : null);
  }

  /// Saves the chosen [mode], creating the profile on first use.
  Future<void> setMode(User user, AppMode mode, {required bool isNew}) {
    return settleWrite(
      _doc(user.uid).set({
        'displayName': user.displayName,
        'email': user.email,
        'photoURL': user.photoURL,
        'mode': mode.name,
        'updatedAt': FieldValue.serverTimestamp(),
        if (isNew) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
    );
  }
}
