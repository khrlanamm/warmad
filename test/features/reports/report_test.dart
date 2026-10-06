import 'package:flutter_test/flutter_test.dart';
import 'package:warmad/features/reports/domain/report.dart';

void main() {
  group('DailySummary', () {
    const day = DailySummary(
      salesCash: 979400,
      salesCredit: 30000,
      debtCollected: 20000,
      purchasesCash: 134400,
      purchasesDebt: 500000,
      supplierPayments: 50000,
      expenses: 100000,
      prive: 75000,
      refunds: 8000,
    );

    test('cash in is cash sales plus kasbon paid back', () {
      expect(day.cashIn, 999400);
    });

    test('kasbon sales and stock bought on debt are not cash', () {
      const noCash = DailySummary(salesCredit: 30000, purchasesDebt: 500000);
      expect(noCash.cashIn, 0);
      expect(noCash.cashOut, 0);
      expect(day.cashOut, 134400 + 50000 + 100000 + 75000 + 8000);
    });

    test('net is cash in minus cash out', () {
      expect(day.net, 999400 - 367400);
    });

    test('fromMap treats missing fields as zero', () {
      final parsed = DailySummary.fromMap({
        'salesCash': 31000,
        'expenseByCategory': {'Listrik': 25000},
      });
      expect(parsed.cashIn, 31000);
      expect(parsed.cashOut, 0);
      expect(parsed.expenseByCategory, {'Listrik': 25000});
    });
  });

  group('rangeFor', () {
    final anchor = DateTime(2026, 9, 29, 14, 32);

    test('daily covers just that day', () {
      final range = rangeFor(ReportPeriod.daily, anchor);
      expect(range.startKey, '2026-09-29');
      expect(range.endKey, '2026-09-29');
      expect(range.days.length, 1);
    });

    test('weekly covers the seven days ending on the anchor', () {
      // The design shows "23-29 September 2026".
      final range = rangeFor(ReportPeriod.weekly, anchor);
      expect(range.startKey, '2026-09-23');
      expect(range.endKey, '2026-09-29');
      expect(range.days.length, 7);
    });

    test('weekly crosses a month boundary', () {
      final range = rangeFor(ReportPeriod.weekly, DateTime(2026, 10, 2));
      expect(range.startKey, '2026-09-26');
      expect(range.days.length, 7);
    });

    test('monthly covers the whole calendar month', () {
      final september = rangeFor(ReportPeriod.monthly, anchor);
      expect(september.startKey, '2026-09-01');
      expect(september.endKey, '2026-09-30');
      expect(september.days.length, 30);

      final february = rangeFor(ReportPeriod.monthly, DateTime(2028, 2, 10));
      expect(february.endKey, '2028-02-29');
    });
  });

  group('shiftAnchor', () {
    test('moves a day, a week or a month', () {
      final anchor = DateTime(2026, 9, 29);
      expect(
        shiftAnchor(ReportPeriod.daily, anchor, -1),
        DateTime(2026, 9, 28),
      );
      expect(
        shiftAnchor(ReportPeriod.weekly, anchor, -1),
        DateTime(2026, 9, 22),
      );
      expect(
        shiftAnchor(ReportPeriod.weekly, anchor, 1),
        DateTime(2026, 10, 6),
      );
    });

    test('never skips a month from the 31st', () {
      final march = shiftAnchor(ReportPeriod.monthly, DateTime(2026, 1, 31), 1);
      expect(rangeFor(ReportPeriod.monthly, march).startKey, '2026-02-01');
    });
  });

  group('CashFlowReport', () {
    final range = rangeFor(ReportPeriod.weekly, DateTime(2026, 9, 29));
    final report = CashFlowReport(range, {
      '2026-09-28': const DailySummary(
        salesCash: 900000,
        purchasesCash: 400000,
        expenses: 50000,
        expenseByCategory: {'Listrik': 50000},
      ),
      '2026-09-29': const DailySummary(
        salesCash: 979400,
        debtCollected: 20000,
        salesCredit: 30000,
        salesCount: 47,
        purchasesCash: 134400,
        supplierPayments: 100000,
        expenses: 100000,
        prive: 75000,
        expenseByCategory: {'Listrik': 60000, 'Plastik & kemasan': 40000},
      ),
      // Outside the range. Must be ignored.
      '2026-09-01': const DailySummary(salesCash: 5000000),
    });

    test('adds up only the days in the range', () {
      expect(report.cashIn, 900000 + 999400);
      expect(report.cashOut, 450000 + 409400);
      expect(report.net, report.cashIn - report.cashOut);
      expect(report.salesCount, 47);
    });

    test('has one entry per day, including quiet days', () {
      expect(report.days.length, 7);
      expect(report.days.first.summary.cashIn, 0);
      expect(report.days.last.summary.cashIn, 999400);
    });

    test('lists outflows largest first with prive on its own line', () {
      expect(report.outflows, [
        (label: 'Pembelian barang', amount: 634400),
        (label: 'Listrik', amount: 110000),
        (label: 'Diambil untuk pribadi', amount: 75000),
        (label: 'Plastik & kemasan', amount: 40000),
      ]);
    });

    test('outflows add up to cash out', () {
      final total = report.outflows.fold(0, (sum, o) => sum + o.amount);
      expect(total, report.cashOut);
    });

    test('files expenses without a category under Lainnya', () {
      final loose = CashFlowReport(range, {
        '2026-09-29': const DailySummary(expenses: 30000),
      });
      expect(loose.outflows, [(label: 'Lainnya', amount: 30000)]);
    });

    test('knows when nothing happened', () {
      expect(CashFlowReport(range, const {}).isEmpty, isTrue);
      expect(report.isEmpty, isFalse);
    });

    test('exports one CSV row per day plus a total', () {
      final lines = report.toCsv().trim().split('\n');
      expect(lines.length, 1 + 7 + 1);
      expect(lines.first, startsWith('Tanggal,Kas masuk,Kas keluar'));
      expect(lines[7], '2026-09-29,999400,409400,590000,47,30000,75000');
      expect(lines.last, 'Total,1899400,859400,1040000,47,30000,75000');
    });
  });

  group('topSellers', () {
    test('adds up days and ranks by pieces sold', () {
      final ranked = topSellers([
        {'kopi': 80, 'indomie': 40, 'aqua': 30},
        {'kopi': 62, 'indomie': 44, 'aqua': 41, 'teh': 58},
      ], limit: 3);
      expect(ranked, [
        (productId: 'kopi', qty: 142),
        (productId: 'indomie', qty: 84),
        (productId: 'aqua', qty: 71),
      ]);
    });

    test('leaves out products whose sales were all voided', () {
      final ranked = topSellers([
        {'aqua': 7, 'aqua-1500ml': 0, 'salah': -1},
      ]);
      expect(ranked, [(productId: 'aqua', qty: 7)]);
    });

    test('is empty when nothing was sold', () {
      expect(topSellers(const []), isEmpty);
    });
  });
}
