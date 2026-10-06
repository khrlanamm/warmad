import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/money.dart';
import '../../../core/widgets/status_chip.dart';
import '../../products/data/product_repository.dart';
import '../../products/domain/product.dart';
import '../../profile/data/profile_repository.dart';
import '../../warung/data/warung_repository.dart';
import '../data/report_exporter.dart';
import '../data/report_repository.dart';
import '../domain/report.dart';

/// Laporan: cash flow and stock over a day, a week or a month.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  bool _stockTab = false;
  ReportPeriod _period = ReportPeriod.weekly;
  DateTime _anchor = DateTime.now();

  static String _label(ReportPeriod period, DateRange range) {
    String format(String pattern, DateTime day) =>
        DateFormat(pattern, 'id_ID').format(day);
    return switch (period) {
      ReportPeriod.daily => format('EEEE, d MMMM yyyy', range.start),
      ReportPeriod.monthly => format('MMMM yyyy', range.start),
      ReportPeriod.weekly =>
        range.start.month == range.end.month
            ? '${range.start.day}–${format('d MMMM yyyy', range.end)}'
            : '${format('d MMM', range.start)} – '
                  '${format('d MMM yyyy', range.end)}',
    };
  }

  Future<void> _export(CashFlowReport report) async {
    final warungName = ref.read(currentWarungProvider).value?.name ?? 'Warung';
    final format = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.cream,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.fileText),
              title: const Text('Bagikan sebagai PDF'),
              onTap: () => Navigator.of(context).pop('pdf'),
            ),
            ListTile(
              leading: const Icon(LucideIcons.table),
              title: const Text('Bagikan sebagai CSV (untuk Excel)'),
              onTap: () => Navigator.of(context).pop('csv'),
            ),
          ],
        ),
      ),
    );
    if (format == null) return;
    const exporter = ReportExporter();
    try {
      if (format == 'pdf') {
        await exporter.sharePdf(report, warungName);
      } else {
        await exporter.shareCsv(report, warungName);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal membuat file laporan.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final membership = ref.watch(membershipProvider).value;
    if (membership != null && !membership.isOwner) {
      return Scaffold(
        appBar: AppBar(title: const Text('Laporan')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'Laporan hanya bisa dilihat pemilik warung.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: AppColors.inkMuted,
              ),
            ),
          ),
        ),
      );
    }

    final range = rangeFor(_period, _anchor);
    final query = (startKey: range.startKey, endKey: range.endKey);
    final summaries = ref.watch(summariesProvider(query));
    final report = CashFlowReport(range, summaries.value ?? const {});
    final today = DateTime.now();
    final atLatest = !range.end.isBefore(
      DateTime(today.year, today.month, today.day),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton.outlined(
              tooltip: 'Bagikan laporan',
              onPressed: summaries.hasValue ? () => _export(report) : null,
              icon: const Icon(LucideIcons.download),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Arus kas')),
              ButtonSegment(value: true, label: Text('Stok')),
            ],
            selected: {_stockTab},
            onSelectionChanged: (selection) =>
                setState(() => _stockTab = selection.first),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final (period, label) in const [
                (ReportPeriod.daily, 'Harian'),
                (ReportPeriod.weekly, 'Mingguan'),
                (ReportPeriod.monthly, 'Bulanan'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _period == period,
                  onSelected: (_) => setState(() {
                    _period = period;
                    _anchor = DateTime.now();
                  }),
                ),
            ],
          ),
          Row(
            children: [
              const Icon(
                LucideIcons.calendar,
                size: 18,
                color: AppColors.inkMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _label(_period, range),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.inkMuted,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Sebelumnya',
                onPressed: () =>
                    setState(() => _anchor = shiftAnchor(_period, _anchor, -1)),
                icon: const Icon(LucideIcons.chevronLeft),
              ),
              IconButton(
                tooltip: 'Berikutnya',
                onPressed: atLatest
                    ? null
                    : () => setState(
                        () => _anchor = shiftAnchor(_period, _anchor, 1),
                      ),
                icon: const Icon(LucideIcons.chevronRight),
              ),
            ],
          ),
          if (!summaries.hasValue)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_stockTab)
            _StockReport(query: query)
          else
            _CashFlow(report: report, showChart: _period != ReportPeriod.daily),
        ],
      ),
    );
  }
}

class _CashFlow extends StatelessWidget {
  const _CashFlow({required this.report, required this.showChart});

  final CashFlowReport report;
  final bool showChart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget tile(String label, int amount, Color color) => Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodySmall),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  formatRupiah(amount),
                  style: AppText.money(19, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            tile('Kas masuk', report.cashIn, AppColors.green),
            const SizedBox(width: 10),
            tile('Kas keluar', report.cashOut, AppColors.danger),
          ],
        ),
        const SizedBox(height: 10),
        DecoratedBox(
          decoration: BoxDecoration(
            color: report.net < 0 ? AppColors.dangerTint : AppColors.greenTint,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Arus kas bersih', style: theme.textTheme.bodyMedium),
                Text(
                  formatRupiah(report.net, showPlus: true),
                  style: AppText.money(
                    22,
                    color: report.net < 0
                        ? AppColors.danger
                        : AppColors.greenDark,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (report.salesCredit > 0) ...[
          const SizedBox(height: 8),
          Text(
            'Belum termasuk penjualan kasbon '
            '${formatRupiah(report.salesCredit)} yang belum dibayar.',
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (report.isEmpty) ...[
          const SizedBox(height: 32),
          Center(
            child: Text(
              'Belum ada catatan di periode ini.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: AppColors.inkMuted,
              ),
            ),
          ),
        ] else ...[
          if (showChart) ...[
            const SizedBox(height: 12),
            _DailyChart(report: report),
          ],
          if (report.outflows.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Kas keluar terbesar', style: theme.textTheme.titleLarge),
            const SizedBox(height: 10),
            Card(
              child: Column(
                children: [
                  for (final (index, outflow) in report.outflows.indexed) ...[
                    if (index > 0) const Divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(outflow.label, style: theme.textTheme.bodyLarge),
                          Text(
                            formatRupiah(outflow.amount),
                            style: AppText.body(16, weight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
        const SizedBox(height: 12),
        Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            title: const Text('Riwayat tutup kas dan selisihnya'),
            trailing: const Icon(LucideIcons.chevronRight),
            onTap: () => context.push(Routes.warungCashHistory),
          ),
        ),
      ],
    );
  }
}

/// Cash in and cash out side by side for each day of the range.
class _DailyChart extends StatelessWidget {
  const _DailyChart({required this.report});

  final CashFlowReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = report.days;
    final many = days.length > 10;
    final peak = days.fold<int>(
      1,
      (max, entry) => [
        max,
        entry.summary.cashIn,
        entry.summary.cashOut,
      ].reduce((a, b) => a > b ? a : b),
    );

    Widget legend(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(radius: 5, backgroundColor: color),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Per hari', style: theme.textTheme.titleSmall),
                  ),
                  legend(AppColors.green, 'Masuk'),
                  const SizedBox(width: 12),
                  legend(AppColors.yellow, 'Keluar'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 170,
              child: BarChart(
                BarChartData(
                  maxY: peak * 1.1,
                  alignment: BarChartAlignment.spaceAround,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => AppColors.ink,
                      getTooltipItem: (group, _, rod, rodIndex) =>
                          BarTooltipItem(
                            '${rodIndex == 0 ? 'Masuk' : 'Keluar'}\n'
                            '${formatRupiah(rod.toY.round())}',
                            AppText.body(12, color: AppColors.white),
                          ),
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    topTitles: const AxisTitles(),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        getTitlesWidget: (value, _) {
                          final index = value.toInt();
                          if (index < 0 || index >= days.length) {
                            return const SizedBox.shrink();
                          }
                          final day = days[index].day;
                          // A month has too many days to label each one.
                          if (many && day.day != 1 && day.day % 5 != 0) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              many
                                  ? '${day.day}'
                                  : DateFormat('E', 'id_ID').format(day),
                              style: theme.textTheme.bodySmall,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (final (index, entry) in days.indexed)
                      BarChartGroupData(
                        x: index,
                        barsSpace: many ? 1 : 3,
                        barRods: [
                          for (final (amount, color) in [
                            (entry.summary.cashIn, AppColors.green),
                            (entry.summary.cashOut, AppColors.yellow),
                          ])
                            BarChartRodData(
                              toY: amount.toDouble(),
                              color: color,
                              width: many ? 3 : 12,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(3),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StockReport extends ConsumerWidget {
  const _StockReport({required this.query});

  final ReportQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final products = ref.watch(productsProvider).value ?? const <Product>[];
    final byId = {for (final product in products) product.id: product};
    final best = topSellers(
      (ref.watch(productSalesProvider(query)).value ?? const {}).values,
    );
    final low =
        products.where((p) => p.active && p.status != StockStatus.aman).toList()
          ..sort(compareByUrgency);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Barang terlaris', style: theme.textTheme.titleLarge),
        const SizedBox(height: 10),
        if (best.isEmpty)
          Text(
            'Belum ada penjualan di periode ini.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.inkMuted,
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (final (index, entry) in best.indexed) ...[
                  if (index > 0) const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 13,
                          backgroundColor: AppColors.greenTint,
                          child: Text(
                            '${index + 1}',
                            style: AppText.body(
                              13,
                              weight: FontWeight.w700,
                              color: AppColors.green,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            byId[entry.productId]?.name ?? 'Barang dihapus',
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                        Text(
                          '${formatNumber(entry.qty)} pcs',
                          style: AppText.body(16, weight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 24),
        Text('Hampir habis dan habis', style: theme.textTheme.titleLarge),
        const SizedBox(height: 10),
        if (low.isEmpty)
          Text(
            'Semua stok aman.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.inkMuted,
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (final (index, product) in low.indexed) ...[
                  if (index > 0) const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product.name,
                                style: theme.textTheme.bodyLarge,
                              ),
                              Text(
                                'Stok ${formatNumber(product.stock)}, '
                                'batas pesan ${product.reorderPoint}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        product.status == StockStatus.habis
                            ? const StatusChip(
                                label: 'Habis',
                                tone: StatusTone.danger,
                              )
                            : const StatusChip(
                                label: 'Hampir habis',
                                tone: StatusTone.warning,
                              ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
