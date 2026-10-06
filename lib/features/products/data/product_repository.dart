import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../profile/data/profile_repository.dart';
import '../domain/product.dart';

final productRepositoryProvider = Provider<ProductRepository>(
  (ref) => ProductRepository(ref.watch(firestoreProvider)),
);

/// Every product of the current warung, including retired ones, kept in
/// memory so search at the till is instant and works offline.
final productsProvider = StreamProvider<List<Product>>((ref) {
  final membership = ref.watch(membershipProvider.select((m) => m.value));
  if (membership == null) return Stream.value(const []);
  return ref.watch(productRepositoryProvider).watchAll(membership.warungId);
});

class ProductRepository {
  ProductRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _products(String warungId) =>
      _db.collection('warungs/$warungId/products');

  /// Streams all products while reading as little as possible from the server.
  ///
  /// The list is loaded from the local cache first. The listener then only
  /// asks for products changed after the newest one already cached, so opening
  /// the app does not re-read the whole collection. This relies on two things:
  /// every write stamps `updatedAt`, and products are never deleted.
  Stream<List<Product>> watchAll(String warungId) async* {
    final collection = _products(warungId);
    final products = <String, Product>{};
    Timestamp? newest;

    try {
      final cached = await collection.get(
        const GetOptions(source: Source.cache),
      );
      for (final doc in cached.docs) {
        products[doc.id] = Product.fromMap(doc.id, doc.data());
        // A pending local write has no server timestamp yet.
        final updatedAt = doc.data()['updatedAt'];
        if (updatedAt is Timestamp &&
            (newest == null || updatedAt.compareTo(newest) > 0)) {
          newest = updatedAt;
        }
      }
    } on FirebaseException {
      // Nothing cached yet; the listener below loads everything once.
    }
    yield _sorted(products);

    final changes = newest == null
        ? collection
        : collection.where('updatedAt', isGreaterThan: newest);
    await for (final snapshot in changes.snapshots()) {
      for (final change in snapshot.docChanges) {
        final data = change.doc.data();
        if (change.type == DocumentChangeType.removed || data == null) continue;
        products[change.doc.id] = Product.fromMap(change.doc.id, data);
      }
      yield _sorted(products);
    }
  }

  static List<Product> _sorted(Map<String, Product> products) =>
      products.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  static Map<String, dynamic> _fields(ProductDraft draft) => {
    'name': draft.name,
    'category': draft.category,
    'barcode': draft.barcode,
    'sellPrice': draft.sellPrice,
    'lastBuyPrice': draft.lastBuyPrice,
    'pack': draft.pack?.toMap(),
    'manualRop': draft.manualRop,
    'manualOrderQty': draft.manualOrderQty,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  Future<void> add(String warungId, ProductDraft draft) {
    return settleWrite(
      _products(warungId).doc().set({
        ..._fields(draft),
        'unit': 'pcs',
        'stock': draft.initialStock,
        'active': true,
        if (draft.catalogId != null) 'catalogId': draft.catalogId,
        'createdAt': FieldValue.serverTimestamp(),
      }),
    );
  }

  Future<void> update(String warungId, Product current, ProductDraft draft) {
    final identityChanged =
        draft.name != current.name || draft.barcode != current.barcode;
    return settleWrite(
      _products(warungId).doc(current.id).update({
        ..._fields(draft),
        // A renamed or re-scanned product may be a different catalog item.
        // Dropping the link makes Cloud Functions look it up again.
        if (draft.catalogId != null && draft.catalogId != current.catalogId)
          'catalogId': draft.catalogId
        else if (identityChanged)
          'catalogId': FieldValue.delete(),
      }),
    );
  }

  /// Retires or restores a product. Products are never deleted so that past
  /// sales keep pointing at them.
  Future<void> setActive(String warungId, String productId, bool active) {
    return settleWrite(
      _products(warungId).doc(productId).update({
        'active': active,
        'updatedAt': FieldValue.serverTimestamp(),
      }),
    );
  }
}
