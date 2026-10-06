import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../profile/data/profile_repository.dart';
import '../domain/report.dart';

final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => ReportRepository(ref.watch(firestoreProvider)),
);

typedef ReportQuery = ({String startKey, String endKey});

/// Daily summaries of the current warung between two day keys, by day key.
final summariesProvider = StreamProvider.autoDispose
    .family<Map<String, DailySummary>, ReportQuery>((ref, query) {
      final membership = ref.watch(membershipProvider.select((m) => m.value));
      if (membership == null) return Stream.value(const {});
      return ref
          .watch(reportRepositoryProvider)
          .watchSummaries(membership.warungId, query.startKey, query.endKey);
    });

/// Pieces sold per product for each day between two day keys.
final productSalesProvider = StreamProvider.autoDispose
    .family<List<Map<String, int>>, ReportQuery>((ref, query) {
      final membership = ref.watch(membershipProvider.select((m) => m.value));
      if (membership == null) return Stream.value(const []);
      return ref
          .watch(reportRepositoryProvider)
          .watchProductSales(membership.warungId, query.startKey, query.endKey);
    });

/// Reads the small per-day report documents. A month is at most 31 reads,
/// however many transactions it holds.
class ReportRepository {
  ReportRepository(this._db);

  final FirebaseFirestore _db;

  Query<Map<String, dynamic>> _days(
    String warungId,
    String collection,
    String startKey,
    String endKey,
  ) => _db
      .collection('warungs/$warungId/$collection')
      .orderBy(FieldPath.documentId)
      .startAt([startKey])
      .endAt([endKey]);

  Stream<Map<String, DailySummary>> watchSummaries(
    String warungId,
    String startKey,
    String endKey,
  ) => _days(warungId, 'dailySummaries', startKey, endKey).snapshots().map(
    (snapshot) => {
      for (final doc in snapshot.docs) doc.id: DailySummary.fromMap(doc.data()),
    },
  );

  Stream<List<Map<String, int>>> watchProductSales(
    String warungId,
    String startKey,
    String endKey,
  ) => _days(warungId, 'dailyProductSales', startKey, endKey).snapshots().map(
    (snapshot) => [
      for (final doc in snapshot.docs)
        {
          for (final entry
              in (doc.data()['qty'] as Map<String, dynamic>? ?? const {})
                  .entries)
            entry.key: (entry.value as num?)?.toInt() ?? 0,
        },
    ],
  );
}
