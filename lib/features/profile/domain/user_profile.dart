import 'package:cloud_firestore/cloud_firestore.dart';

/// Which side of the app the user is currently using.
enum AppMode {
  warung,
  pembeli;

  static AppMode? parse(Object? value) =>
      AppMode.values.where((m) => m.name == value).firstOrNull;
}

enum WarungRole {
  owner,
  cashier;

  static WarungRole? parse(Object? value) =>
      WarungRole.values.where((r) => r.name == value).firstOrNull;
}

/// The `users/{uid}` document.
class UserProfile {
  const UserProfile({
    required this.uid,
    this.displayName,
    this.email,
    this.photoURL,
    this.mode,
    this.warungId,
    this.role,
    this.claimsUpdatedAt,
  });

  factory UserProfile.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const {};
    return UserProfile(
      uid: snapshot.id,
      displayName: data['displayName'] as String?,
      email: data['email'] as String?,
      photoURL: data['photoURL'] as String?,
      mode: AppMode.parse(data['mode']),
      warungId: data['warungId'] as String?,
      role: WarungRole.parse(data['role']),
      claimsUpdatedAt: data['claimsUpdatedAt'] as Timestamp?,
    );
  }

  final String uid;
  final String? displayName;
  final String? email;
  final String? photoURL;
  final AppMode? mode;

  /// Mirror of the `wid` and `role` custom claims, written by Cloud Functions.
  final String? warungId;
  final WarungRole? role;

  /// Changes whenever Cloud Functions set new claims for this account.
  final Timestamp? claimsUpdatedAt;
}

/// The warung an account belongs to, taken from its ID token claims.
class Membership {
  const Membership({required this.warungId, required this.role});

  final String warungId;
  final WarungRole role;

  bool get isOwner => role == WarungRole.owner;

  @override
  bool operator ==(Object other) =>
      other is Membership && other.warungId == warungId && other.role == role;

  @override
  int get hashCode => Object.hash(warungId, role);
}
