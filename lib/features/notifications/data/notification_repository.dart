import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../profile/data/profile_repository.dart';

/// An entry in the owner's notification list
/// (`warungs/{id}/notifications/{id}`), written by Cloud Functions.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
    this.productId,
  });

  final String id;

  /// lowStock, outOfStock, cashClosed or closingReminder.
  final String type;
  final String title;
  final String body;
  final bool read;
  final DateTime createdAt;

  /// Set for stock alerts.
  final String? productId;
}

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(ref.watch(firestoreProvider)),
);

/// The latest notifications of the current warung, newest first. Empty for
/// cashiers: notifications are for the owner.
final notificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final membership = ref.watch(membershipProvider.select((m) => m.value));
  if (membership == null || !membership.isOwner) {
    return Stream.value(const []);
  }
  return ref.watch(notificationRepositoryProvider).watch(membership.warungId);
});

final unreadNotificationsProvider = Provider<int>(
  (ref) => (ref.watch(notificationsProvider).value ?? const [])
      .where((notification) => !notification.read)
      .length,
);

class NotificationRepository {
  NotificationRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _notifications(String warungId) =>
      _db.collection('warungs/$warungId/notifications');

  Stream<List<AppNotification>> watch(String warungId, {int limit = 30}) {
    return _notifications(warungId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => [
            for (final doc in snapshot.docs)
              AppNotification(
                id: doc.id,
                type: doc.data()['type'] as String? ?? '',
                title: doc.data()['title'] as String? ?? '',
                body: doc.data()['body'] as String? ?? '',
                read: doc.data()['read'] as bool? ?? false,
                createdAt:
                    (doc.data()['createdAt'] as Timestamp?)?.toDate() ??
                    DateTime.now(),
                productId: doc.data()['productId'] as String?,
              ),
          ],
        );
  }

  Future<void> markRead(String warungId, Iterable<String> ids) {
    final batch = _db.batch();
    for (final id in ids) {
      batch.update(_notifications(warungId).doc(id), {'read': true});
    }
    return settleWrite(batch.commit());
  }
}
