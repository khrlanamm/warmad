import '../../../core/dates.dart';

/// One day of activity (`warungs/{id}/dailySummaries/{dayKey}`), kept up to
/// date by Cloud Functions so reports never re-add single transactions.
class DailySummary {
  const DailySummary({
    this.salesCash = 0,
    this.salesCredit = 0,
    this.salesCount = 0,
    this.itemsSold = 0,
    this.debtCollected = 0,
    this.purchasesCash = 0,
    this.purchasesDebt = 0,
    this.supplierPayments = 0,
    this.expenses = 0,
    this.prive = 0,
    this.refunds = 0,
    this.expenseByCategory = const {},
  });

  factory DailySummary.fromMap(Map<String, dynamic> data) {
    int amount(String key) => (data[key] as num?)?.toInt() ?? 0;
    final categories = data['expenseByCategory'];
    return DailySummary(
      salesCash: amount('salesCash'),
      salesCredit: amount('salesCredit'),
      salesCount: amount('salesCount'),
      itemsSold: amount('itemsSold'),
      debtCollected: amount('debtCollected'),
      purchasesCash: amount('purchasesCash'),
      purchasesDebt: amount('purchasesDebt'),
      supplierPayments: amount('supplierPayments'),
      expenses: amount('expenses'),
      prive: amount('prive'),
      refunds: amount('refunds'),
      expenseByCategory: {
        if (categories is Map)
          for (final entry in categories.entries)
            '${entry.key}': (entry.value as num?)?.toInt() ?? 0,
      },
    );
  }

  final int salesCash;

  /// Sold on kasbon. Not cash yet.
  final int salesCredit;
  final int salesCount;
  final int itemsSold;
  final int debtCollected;
  final int purchasesCash;

  /// Stock bought on supplier debt. No cash left the drawer.
  final int purchasesDebt;
  final int supplierPayments;
  final int expenses;
  final int prive;
  final int refunds;
  final Map<String, int> expenseByCategory;

  /// Cash that came into the drawer.
  int get cashIn => salesCash + debtCollected;

  /// Cash that left the drawer, for the business or for the owner.
  int get cashOut =>
      purchasesCash + supplierPayments + expenses + prive + refunds;

  int get net => cashIn - cashOut;
}

enum ReportPeriod { daily, weekly, monthly }

/// A run of whole days, both ends included.
class DateRange {
  DateRange(DateTime start, DateTime end)
    : start = DateTime(start.year, start.month, start.day),
      end = DateTime(end.year, end.month, end.day);

  final DateTime start;
  final DateTime end;

  List<DateTime> get days => [
    for (
      var day = start;
      !day.isAfter(end);
      day = DateTime(day.year, day.month, day.day + 1)
    )
      day,
  ];

  String get startKey => dayKeyOf(start);
  String get endKey => dayKeyOf(end);
}

/// The range a report covers: the day itself, the seven days ending on
/// [anchor], or the calendar month [anchor] falls in.
DateRange rangeFor(ReportPeriod period, DateTime anchor) => switch (period) {
  ReportPeriod.daily => DateRange(anchor, anchor),
  ReportPeriod.weekly => DateRange(
    DateTime(anchor.year, anchor.month, anchor.day - 6),
    anchor,
  ),
  ReportPeriod.monthly => DateRange(
    DateTime(anchor.year, anchor.month),
    DateTime(anchor.year, anchor.month + 1, 0),
  ),
};

/// The anchor of the previous ([steps] negative) or next range.
DateTime shiftAnchor(ReportPeriod period, DateTime anchor, int steps) =>
    switch (period) {
      ReportPeriod.daily => DateTime(
        anchor.year,
        anchor.month,
        anchor.day + steps,
      ),
      ReportPeriod.weekly => DateTime(
        anchor.year,
        anchor.month,
        anchor.day + 7 * steps,
      ),
      // Day 1 avoids skipping a month from, say, the 31st.
      ReportPeriod.monthly => DateTime(anchor.year, anchor.month + steps),
    };

/// Cash flow over a range of days.
class CashFlowReport {
  CashFlowReport(this.range, Map<String, DailySummary> byDay)
    : days = [
        for (final day in range.days)
          (day: day, summary: byDay[dayKeyOf(day)] ?? const DailySummary()),
      ];

  final DateRange range;

  /// One entry per day of the range, including days with no activity.
  final List<({DateTime day, DailySummary summary})> days;

  int _sum(int Function(DailySummary s) pick) =>
      days.fold(0, (sum, entry) => sum + pick(entry.summary));

  int get cashIn => _sum((s) => s.cashIn);
  int get cashOut => _sum((s) => s.cashOut);
  int get net => cashIn - cashOut;
  int get salesCount => _sum((s) => s.salesCount);
  int get salesCredit => _sum((s) => s.salesCredit);
  int get prive => _sum((s) => s.prive);

  bool get isEmpty => cashIn == 0 && cashOut == 0 && salesCredit == 0;

  /// Where the cash went, largest first. Prive is listed apart from the
  /// business expenses so the two are never confused.
  List<({String label, int amount})> get outflows {
    final amounts = <String, int>{
      'Pembelian barang': _sum((s) => s.purchasesCash + s.supplierPayments),
      'Diambil untuk pribadi': prive,
      'Penjualan dibatalkan': _sum((s) => s.refunds),
    };
    var categorised = 0;
    for (final entry in days) {
      entry.summary.expenseByCategory.forEach((category, amount) {
        amounts[category] = (amounts[category] ?? 0) + amount;
        categorised += amount;
      });
    }
    // Expenses recorded before categories were tracked.
    final uncategorised = _sum((s) => s.expenses) - categorised;
    if (uncategorised > 0) {
      amounts['Lainnya'] = (amounts['Lainnya'] ?? 0) + uncategorised;
    }
    final list = [
      for (final entry in amounts.entries)
        if (entry.value > 0) (label: entry.key, amount: entry.value),
    ]..sort((a, b) => b.amount.compareTo(a.amount));
    return list;
  }

  /// The report as CSV, one row per day, for sharing or a spreadsheet.
  String toCsv() {
    final rows = [
      'Tanggal,Kas masuk,Kas keluar,Arus kas bersih,Jumlah penjualan,'
          'Penjualan kasbon,Diambil untuk pribadi',
      for (final entry in days)
        [
          dayKeyOf(entry.day),
          entry.summary.cashIn,
          entry.summary.cashOut,
          entry.summary.net,
          entry.summary.salesCount,
          entry.summary.salesCredit,
          entry.summary.prive,
        ].join(','),
      ['Total', cashIn, cashOut, net, salesCount, salesCredit, prive].join(','),
    ];
    return '${rows.join('\n')}\n';
  }
}

/// Adds up pieces sold per product over several days and returns the
/// best sellers, most pieces first. Products at zero or below (fully voided)
/// are left out.
List<({String productId, int qty})> topSellers(
  Iterable<Map<String, int>> dailyQty, {
  int limit = 5,
}) {
  final totals = <String, int>{};
  for (final day in dailyQty) {
    day.forEach((productId, qty) {
      totals[productId] = (totals[productId] ?? 0) + qty;
    });
  }
  final ranked =
      [
        for (final entry in totals.entries)
          if (entry.value > 0) (productId: entry.key, qty: entry.value),
      ]..sort((a, b) {
        final byQty = b.qty.compareTo(a.qty);
        return byQty != 0 ? byQty : a.productId.compareTo(b.productId);
      });
  return ranked.take(limit).toList();
}
