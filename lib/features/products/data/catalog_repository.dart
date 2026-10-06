import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../domain/product.dart';

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepository(ref.watch(firestoreProvider)),
);

/// An item in the shared catalog (`catalog/{id}`), common to all warungs.
class CatalogEntry {
  const CatalogEntry({
    required this.id,
    required this.name,
    this.category,
    this.pack,
  });

  factory CatalogEntry.fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    return CatalogEntry(
      id: snapshot.id,
      name: data['name'] as String? ?? '',
      category: data['category'] as String?,
      pack: PackUnit.fromMap({
        'name': data['packName'],
        'size': data['packSize'],
      }),
    );
  }

  final String id;
  final String name;
  final String? category;
  final PackUnit? pack;
}

/// Lowercases [text] and splits it into letter and digit runs, the same way
/// catalog entries are indexed.
List<String> searchWords(String text) => text
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((word) => word.isNotEmpty)
    .toList();

class CatalogRepository {
  CatalogRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _catalog =>
      _db.collection('catalog');

  /// Catalog entries whose name contains every word typed so far.
  ///
  /// Firestore matches one word prefix on the server; the remaining words are
  /// checked here. Returns nothing while offline and nothing is cached.
  Future<List<CatalogEntry>> suggest(String text, {int limit = 6}) async {
    final words = searchWords(text);
    final longest = words
        .where((w) => w.length >= 2)
        .fold<String?>(
          null,
          (best, w) => best == null || w.length > best.length ? w : best,
        );
    if (longest == null) return const [];

    // Indexed prefixes stop at 12 letters.
    final prefix = longest.length > 12 ? longest.substring(0, 12) : longest;
    try {
      final result = await _catalog
          .where('prefixes', arrayContains: prefix)
          .limit(30)
          .get();
      return result.docs
          .map(CatalogEntry.fromSnapshot)
          .where((entry) {
            final name = entry.name.toLowerCase();
            return words.every(name.contains);
          })
          .take(limit)
          .toList();
    } on FirebaseException {
      return const [];
    }
  }

  /// The catalog entry a scanned [barcode] belongs to, if any warung has
  /// scanned it before.
  Future<CatalogEntry?> byBarcode(String barcode) async {
    try {
      final result = await _catalog
          .where('barcodes', arrayContains: barcode)
          .limit(1)
          .get();
      return result.docs.isEmpty
          ? null
          : CatalogEntry.fromSnapshot(result.docs.first);
    } on FirebaseException {
      return null;
    }
  }
}
