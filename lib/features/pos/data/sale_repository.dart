import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../profile/data/profile_repository.dart';
import '../domain/cart.dart';
import '../domain/sale.dart';

final saleRepositoryProvider = Provider<SaleRepository>(
  (ref) => SaleRepository(ref.watch(firestoreProvider)),
);

/// The latest sales of the current warung, newest first.
final recentSalesProvider = StreamProvider<List<Sale>>((ref) {
  final membership = ref.watch(membershipProvider.select((m) => m.value));
  if (membership == null) return Stream.value(const []);
  return ref.watch(saleRepositoryProvider).watchRecent(membership.warungId);
});

/// The cart at the till. Kept outside the screen so it survives switching
/// tabs in the middle of a sale.
final cartProvider = NotifierProvider<CartNotifier, Cart>(CartNotifier.new);

class CartNotifier extends Notifier<Cart> {
  @override
  Cart build() => const Cart();

  void update(Cart Function(Cart cart) change) => state = change(state);

  void clear() => state = const Cart();
}

class SaleRepository {
  SaleRepository(this._db);

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _warung(String id) =>
      _db.doc('warungs/$id');

  String newId(String warungId) =>
      _warung(warungId).collection('sales').doc().id;

  /// Saves [sale], takes its items out of stock and adds its total to the
  /// cash counters (or to the customer's balance for kasbon), as one batch.
  ///
  /// A batch is atomic on the server and works offline, where it is applied
  /// to the local cache at once and queued. `increment` keeps stock and cash
  /// right when two phones sell at the same moment. A transaction would do
  /// neither offline.
  ///
  /// The returned future completes only when the server confirms, so the
  /// till must not wait for it.
  Future<void> record(String warungId, Sale sale) {
    final warung = _warung(warungId);
    final batch = _db.batch();

    batch.set(warung.collection('sales').doc(sale.id), {
      ...sale.toMap(),
      'occurredAt': Timestamp.fromDate(sale.occurredAt),
      'createdAt': FieldValue.serverTimestamp(),
    });
    for (final item in sale.items) {
      batch.update(warung.collection('products').doc(item.productId), {
        'stock': FieldValue.increment(-item.qty),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    // Security Rules use `lastTx` to check the amounts against the sale.
    final lastTx = {'kind': 'sales', 'id': sale.id};
    if (sale.onCredit) {
      // Kasbon: no cash comes in. The customer owes the total instead.
      batch.update(warung.collection('customers').doc(sale.customerId), {
        'balance': FieldValue.increment(sale.total),
        'lastTx': lastTx,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      batch.update(warung.collection('cash').doc('current'), {
        'salesCash': FieldValue.increment(sale.total),
        'salesCount': FieldValue.increment(1),
        'lastTx': lastTx,
      });
    }
    return batch.commit();
  }

  Stream<List<Sale>> watchRecent(String warungId, {int limit = 10}) {
    return _warung(warungId)
        .collection('sales')
        .orderBy('occurredAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => [
            for (final doc in snapshot.docs)
              Sale.fromMap(
                doc.id,
                doc.data(),
                occurredAt:
                    (doc.data()['occurredAt'] as Timestamp?)?.toDate() ??
                    DateTime.now(),
              ),
          ],
        );
  }
}
