import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../profile/data/profile_repository.dart';
import '../../warung/data/warung_repository.dart';
import '../domain/cash_closing.dart';

final cashRepositoryProvider = Provider<CashRepository>(
  (ref) => CashRepository(ref.watch(firestoreProvider)),
);

/// Past closings of the current warung, newest first.
final cashClosingsProvider = StreamProvider<List<CashClosing>>((ref) {
  final membership = ref.watch(membershipProvider.select((m) => m.value));
  if (membership == null) return Stream.value(const []);
  return ref.watch(cashRepositoryProvider).watchClosings(membership.warungId);
});

/// Cash records that a phone made before the open period started but that
/// only reached the server afterwards.
typedef LateRecords = ({int count, int net});

/// Late records in the open period of the current warung.
final lateRecordsProvider = StreamProvider.autoDispose<LateRecords>((ref) {
  final membership = ref.watch(membershipProvider.select((m) => m.value));
  final openedAt = ref.watch(
    cashStateProvider.select((cash) => cash.value?.openedAt),
  );
  if (membership == null || openedAt == null) {
    return Stream.value((count: 0, net: 0));
  }
  return ref
      .watch(cashRepositoryProvider)
      .watchLate(membership.warungId, openedAt);
});

class CashRepository {
  CashRepository(this._db);

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _warung(String id) =>
      _db.doc('warungs/$id');

  /// Saves [closing] and starts the next period, as one batch.
  ///
  /// The counters are reduced by the closed figures instead of being set to
  /// zero. A sale another phone made that this phone had not loaded yet then
  /// stays in the counters and falls into the next period, rather than being
  /// wiped out. Works offline like a sale does.
  ///
  /// The server rejects the batch when the period was already closed from
  /// another phone, so the returned future must be listened to for errors.
  Future<void> close(String warungId, CashClosing closing) {
    final warung = _warung(warungId);
    final id = '${closing.seq}';
    final closedAt = Timestamp.fromDate(closing.closedAt);
    final batch = _db.batch();

    batch.set(warung.collection('cashClosings').doc(id), {
      ...closing.toMap(),
      'openedAt': closing.openedAt == null
          ? null
          : Timestamp.fromDate(closing.openedAt!),
      'closedAt': closedAt,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(warung.collection('cash').doc('current'), {
      'salesCash': FieldValue.increment(-closing.salesCash),
      'debtCollected': FieldValue.increment(-closing.debtCollected),
      'purchasesCash': FieldValue.increment(-closing.purchasesCash),
      'expenses': FieldValue.increment(-closing.expenses),
      'prive': FieldValue.increment(-closing.prive),
      'refunds': FieldValue.increment(-closing.refunds),
      'salesCount': FieldValue.increment(-closing.salesCount),
      'openingBalance': closing.counted,
      'seq': FieldValue.increment(1),
      'openedAt': closedAt,
      'lastTx': {'kind': 'cashClosings', 'id': id},
    });
    return batch.commit();
  }

  /// Counts the late cash sales since [openedAt] and adds up what they do
  /// to the cash on record. Cloud Functions mark a sale as late when it was
  /// made before the open period started but synced after it.
  ///
  /// Their cash was already in the drawer when the previous period was
  /// counted, so it showed up as a surplus then and makes the cash look
  /// short by the same amount now.
  Stream<LateRecords> watchLate(String warungId, DateTime openedAt) {
    return _warung(warungId)
        .collection('sales')
        .where('late', isEqualTo: true)
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(openedAt),
        )
        .limit(50)
        .snapshots()
        .map(
          (snapshot) => (
            count: snapshot.docs.length,
            net: snapshot.docs.fold<int>(
              0,
              (net, doc) => net + ((doc.data()['total'] as num?)?.toInt() ?? 0),
            ),
          ),
        );
  }

  Stream<List<CashClosing>> watchClosings(String warungId, {int limit = 30}) {
    return _warung(warungId)
        .collection('cashClosings')
        .orderBy('seq', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => [
            for (final doc in snapshot.docs)
              CashClosing.fromMap(
                doc.data(),
                closedAt:
                    (doc.data()['closedAt'] as Timestamp?)?.toDate() ??
                    DateTime.now(),
                openedAt: (doc.data()['openedAt'] as Timestamp?)?.toDate(),
              ),
          ],
        );
  }
}
