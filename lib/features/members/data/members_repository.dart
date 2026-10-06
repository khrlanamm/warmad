import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../auth/data/auth_service.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/domain/user_profile.dart';

/// Someone who works at the warung (`warungs/{id}/members/{uid}`).
class Member {
  const Member({
    required this.uid,
    required this.role,
    this.displayName,
    this.email,
  });

  final String uid;
  final WarungRole role;
  final String? displayName;
  final String? email;

  String get name => displayName ?? email ?? 'Tanpa nama';
}

final membersRepositoryProvider = Provider<MembersRepository>(
  (ref) => MembersRepository(
    ref.watch(firestoreProvider),
    ref.watch(functionsProvider),
  ),
);

/// Owner first, then cashiers by name.
final membersProvider = StreamProvider<List<Member>>((ref) {
  final membership = ref.watch(membershipProvider.select((m) => m.value));
  if (membership == null) return Stream.value(const []);
  return ref.watch(membersRepositoryProvider).watch(membership.warungId);
});

/// Inviting, joining and removing run on the server, because they grant or
/// take away the claims that give access to the warung. They need a
/// connection.
class MembersRepository {
  MembersRepository(this._db, this._functions);

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  Stream<List<Member>> watch(String warungId) {
    return _db.collection('warungs/$warungId/members').snapshots().map((
      snapshot,
    ) {
      final members = [
        for (final doc in snapshot.docs)
          Member(
            uid: doc.id,
            role: WarungRole.parse(doc.data()['role']) ?? WarungRole.cashier,
            displayName: doc.data()['displayName'] as String?,
            email: doc.data()['email'] as String?,
          ),
      ];
      return members..sort((a, b) {
        if (a.role != b.role) return a.role == WarungRole.owner ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    });
  }

  /// Creates a one-time invite code that is valid for 24 hours.
  Future<String> createInvite() async {
    final result = await _functions
        .httpsCallable('createInvite')
        .call<Map<Object?, Object?>>();
    return result.data['code']! as String;
  }

  /// Joins a warung as cashier with [code]. Returns the warung's name.
  Future<String> acceptInvite(String code, AuthService auth) async {
    final result = await _functions
        .httpsCallable('acceptInvite')
        .call<Map<Object?, Object?>>({'code': code});
    // Pick up the new `wid` and `role` claims right away.
    await auth.currentUser?.getIdToken(true);
    return result.data['warungName'] as String? ?? '';
  }

  Future<void> remove(String uid) async {
    await _functions.httpsCallable('removeMember').call<void>({'uid': uid});
  }
}
