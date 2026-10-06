/// Running counters of the open cash period (`warungs/{id}/cash/current`).
///
/// A period runs from one cash closing to the next. All amounts are whole
/// Rupiah.
class CashState {
  const CashState({
    required this.seq,
    required this.openingBalance,
    this.salesCash = 0,
    this.debtCollected = 0,
    this.purchasesCash = 0,
    this.expenses = 0,
    this.prive = 0,
    this.salesCount = 0,
    this.openedAt,
  });

  factory CashState.fromMap(Map<String, dynamic> data, {DateTime? openedAt}) {
    int amount(String key) => (data[key] as num?)?.toInt() ?? 0;
    return CashState(
      seq: amount('seq'),
      openingBalance: amount('openingBalance'),
      salesCash: amount('salesCash'),
      debtCollected: amount('debtCollected'),
      purchasesCash: amount('purchasesCash'),
      expenses: amount('expenses'),
      prive: amount('prive'),
      salesCount: amount('salesCount'),
      openedAt: openedAt,
    );
  }

  /// Number of the open period, starting at 1.
  final int seq;

  /// Cash counted at the previous closing.
  final int openingBalance;

  /// Sales paid in cash.
  final int salesCash;

  /// Customer credit (kasbon) paid back in cash.
  final int debtCollected;

  /// Stock bought with cash, including supplier debt paid off.
  final int purchasesCash;

  /// Business expenses.
  final int expenses;

  /// Money the owner took for personal use. It leaves the drawer but is not
  /// a business cost.
  final int prive;

  final int salesCount;
  final DateTime? openedAt;

  int get cashIn => salesCash + debtCollected;
  int get cashOut => purchasesCash + expenses + prive;

  /// What should be in the drawer according to the records.
  int get expected => openingBalance + cashIn - cashOut;

  /// Counted cash minus [expected]. Negative means cash is missing.
  int differenceFor(int counted) => counted - expected;
}
