import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/dates.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../pos/domain/sale.dart';
import '../../profile/data/profile_repository.dart';
import '../domain/cash_move.dart';

final ledgerRepositoryProvider = Provider<LedgerRepository>(
  (ref) => LedgerRepository(ref.watch(firestoreProvider)),
);

final suppliersProvider = StreamProvider<List<Supplier>>((ref) {
  final membership = ref.watch(membershipProvider.select((m) => m.value));
  if (membership == null) return Stream.value(const []);
  return ref
      .watch(ledgerRepositoryProvider)
      .watchSuppliers(membership.warungId);
});

final customersProvider = StreamProvider<List<Customer>>((ref) {
  final membership = ref.watch(membershipProvider.select((m) => m.value));
  if (membership == null) return Stream.value(const []);
  return ref
      .watch(ledgerRepositoryProvider)
      .watchCustomers(membership.warungId);
});

/// Records everything that is not a sale: stock bought, supplier debt paid,
/// expenses, prive, kasbon paid back and voided sales.
///
/// Like a sale, each record is one write batch, so it is atomic, works
/// offline, and is checked as a whole by the Security Rules. The returned
/// futures complete only when the server confirms, so screens must not wait
/// for them.
class LedgerRepository {
  LedgerRepository(this._db);

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _warung(String id) =>
      _db.doc('warungs/$id');

  String newId(String warungId) =>
      _warung(warungId).collection('cashMoves').doc().id;

  /// Starts a batch with the move itself and, when it moves drawer cash, the
  /// matching cash counter.
  WriteBatch _begin(String warungId, CashMove move) {
    final warung = _warung(warungId);
    final batch = _db.batch();
    batch.set(warung.collection('cashMoves').doc(move.id), {
      ...move.toMap(),
      'occurredAt': Timestamp.fromDate(move.occurredAt),
      'dayKey': dayKeyOf(move.occurredAt),
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (move.cash) {
      batch.update(warung.collection('cash').doc('current'), {
        move.kind.counter: FieldValue.increment(move.amount),
        'lastTx': _link(move),
      });
    }
    return batch;
  }

  // Security Rules use this to check the amounts against the move.
  static Map<String, String> _link(CashMove move) => {
    'kind': 'cashMoves',
    'id': move.id,
  };

  /// Stock coming in. Adds [CashMove.qty] to the product and remembers
  /// [unitCost] as its latest buy price. Paid from cash, or added to what the
  /// warung owes the supplier.
  Future<void> recordPurchase(
    String warungId,
    CashMove move, {
    required int unitCost,
  }) {
    final warung = _warung(warungId);
    final batch = _begin(warungId, move);
    batch.update(warung.collection('products').doc(move.productId), {
      'stock': FieldValue.increment(move.qty!),
      'lastBuyPrice': unitCost,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (move.onDebt) {
      batch.update(warung.collection('suppliers').doc(move.supplierId), {
        'debt': FieldValue.increment(move.amount),
        'lastTx': _link(move),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    return batch.commit();
  }

  Future<void> recordSupplierPayment(String warungId, CashMove move) {
    final batch = _begin(warungId, move);
    batch.update(
      _warung(warungId).collection('suppliers').doc(move.supplierId),
      {
        'debt': FieldValue.increment(-move.amount),
        'lastTx': _link(move),
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
    return batch.commit();
  }

  /// A business expense or prive.
  Future<void> recordExpense(String warungId, CashMove move) =>
      _begin(warungId, move).commit();

  /// A customer paying back kasbon.
  Future<void> recordDebtPayment(String warungId, CashMove move) {
    final batch = _begin(warungId, move);
    batch.update(
      _warung(warungId).collection('customers').doc(move.customerId),
      {
        'balance': FieldValue.increment(-move.amount),
        'lastTx': _link(move),
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
    return batch.commit();
  }

  /// Voids [sale]: marks it, puts its items back in stock, and gives the
  /// money back (from cash, or off the customer's kasbon balance). The sale
  /// document is kept. Only the owner is allowed to do this.
  Future<void> voidSale(String warungId, Sale sale, CashMove refund) {
    final warung = _warung(warungId);
    final batch = _begin(warungId, refund);
    batch.update(warung.collection('sales').doc(sale.id), {
      'voided': true,
      'voidedAt': Timestamp.fromDate(refund.occurredAt),
      'voidedByUid': refund.createdByUid,
      'voidMoveId': refund.id,
    });
    for (final item in sale.items) {
      batch.update(warung.collection('products').doc(item.productId), {
        'stock': FieldValue.increment(item.qty),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    if (sale.onCredit) {
      batch.update(warung.collection('customers').doc(sale.customerId), {
        'balance': FieldValue.increment(-refund.amount),
        'lastTx': _link(refund),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    return batch.commit();
  }

  Stream<List<Supplier>> watchSuppliers(String warungId) => _warung(warungId)
      .collection('suppliers')
      .orderBy('name')
      .snapshots()
      .map(
        (snapshot) => [
          for (final doc in snapshot.docs) Supplier.fromMap(doc.id, doc.data()),
        ],
      );

  Stream<List<Customer>> watchCustomers(String warungId) => _warung(warungId)
      .collection('customers')
      .orderBy('name')
      .snapshots()
      .map(
        (snapshot) => [
          for (final doc in snapshot.docs) Customer.fromMap(doc.id, doc.data()),
        ],
      );

  /// Adds a supplier and returns its ID at once; the write syncs later.
  String addSupplier(String warungId, String name) {
    final doc = _warung(warungId).collection('suppliers').doc();
    doc.set({
      'name': name,
      'debt': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  /// Adds a kasbon customer and returns its ID at once.
  String addCustomer(String warungId, String name) {
    final doc = _warung(warungId).collection('customers').doc();
    doc.set({
      'name': name,
      'balance': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }
}
