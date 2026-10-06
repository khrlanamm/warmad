import '../../warung/domain/cash_state.dart';

/// The record of one closed cash period (`warungs/{id}/cashClosings/{seq}`).
///
/// It freezes what the records said, what was counted in the drawer, and the
/// difference between the two. A closing is never changed afterwards.
class CashClosing {
  const CashClosing({
    required this.seq,
    required this.openingBalance,
    required this.salesCash,
    required this.debtCollected,
    required this.purchasesCash,
    required this.expenses,
    required this.prive,
    required this.salesCount,
    this.refunds = 0,
    required this.counted,
    required this.closedByUid,
    required this.closedByName,
    required this.closedAt,
    this.openedAt,
  });

  /// Closes the period described by [cash] with [counted] Rupiah found in
  /// the drawer.
  factory CashClosing.of(
    CashState cash, {
    required int counted,
    required String closedByUid,
    required String closedByName,
    required DateTime now,
  }) {
    if (counted < 0) throw ArgumentError('Counted cash cannot be negative.');
    return CashClosing(
      seq: cash.seq,
      openingBalance: cash.openingBalance,
      salesCash: cash.salesCash,
      debtCollected: cash.debtCollected,
      purchasesCash: cash.purchasesCash,
      expenses: cash.expenses,
      prive: cash.prive,
      refunds: cash.refunds,
      salesCount: cash.salesCount,
      counted: counted,
      closedByUid: closedByUid,
      closedByName: closedByName,
      closedAt: now,
      openedAt: cash.openedAt,
    );
  }

  factory CashClosing.fromMap(
    Map<String, dynamic> data, {
    required DateTime closedAt,
    DateTime? openedAt,
  }) {
    int amount(String key) => (data[key] as num?)?.toInt() ?? 0;
    return CashClosing(
      seq: amount('seq'),
      openingBalance: amount('openingBalance'),
      salesCash: amount('salesCash'),
      debtCollected: amount('debtCollected'),
      purchasesCash: amount('purchasesCash'),
      expenses: amount('expenses'),
      prive: amount('prive'),
      refunds: amount('refunds'),
      salesCount: amount('salesCount'),
      counted: amount('counted'),
      closedByUid: data['closedByUid'] as String? ?? '',
      closedByName: data['closedByName'] as String? ?? '',
      closedAt: closedAt,
      openedAt: openedAt,
    );
  }

  /// Number of the period that was closed.
  final int seq;
  final int openingBalance;
  final int salesCash;
  final int debtCollected;
  final int purchasesCash;
  final int expenses;
  final int prive;
  final int refunds;
  final int salesCount;

  /// Cash actually found in the drawer. It opens the next period.
  final int counted;
  final String closedByUid;
  final String closedByName;
  final DateTime closedAt;
  final DateTime? openedAt;

  /// What should have been in the drawer according to the records.
  int get expected =>
      openingBalance +
      salesCash +
      debtCollected -
      purchasesCash -
      expenses -
      prive -
      refunds;

  /// Negative when cash is missing, positive when there is too much.
  int get difference => counted - expected;

  /// Fields of the document, without the timestamps the repository adds.
  Map<String, dynamic> toMap() => {
    'seq': seq,
    'openingBalance': openingBalance,
    'salesCash': salesCash,
    'debtCollected': debtCollected,
    'purchasesCash': purchasesCash,
    'expenses': expenses,
    'prive': prive,
    'refunds': refunds,
    'salesCount': salesCount,
    'expected': expected,
    'counted': counted,
    'difference': difference,
    'closedByUid': closedByUid,
    'closedByName': closedByName,
  };
}
