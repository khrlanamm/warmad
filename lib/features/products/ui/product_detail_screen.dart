import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../core/widgets/status_chip.dart';
import '../../profile/data/profile_repository.dart';
import '../../reports/data/report_repository.dart';
import '../../reports/domain/report.dart';
import '../data/product_repository.dart';
import '../domain/product.dart';

/// Detail barang: stock, when to reorder, how much to order, and how the
/// product has been selling.
class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isOwner = ref.watch(membershipProvider).value?.isOwner ?? false;
    final product = ref
        .watch(productsProvider)
        .value
        ?.where((p) => p.id == productId)
        .firstOrNull;

    if (product == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Barang tidak ditemukan.')),
      );
    }

    final (label, tone, color) = switch (product.status) {
      StockStatus.habis => ('Habis', StatusTone.danger, AppColors.danger),
      StockStatus.hampirHabis => (
        'Hampir habis',
        StatusTone.warning,
        AppColors.warning,
      ),
      StockStatus.aman => ('Aman', StatusTone.good, AppColors.ink),
    };
    final pack = product.pack;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Kembali',
          onPressed: () => context.pop(),
          icon: const Icon(LucideIcons.chevronLeft),
        ),
        title: const Text('Detail barang'),
        actions: [
          if (isOwner)
            TextButton(
              onPressed: () =>
                  context.push(Routes.warungProductEdit(product.id)),
              child: const Text('Ubah'),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                children: [
                  Text(product.name, style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        pack == null
                            ? product.category
                            : '${product.category}, ${pack.size} pcs per '
                                  '${pack.name}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.inkMuted,
                        ),
                      ),
                      StatusChip(label: label, tone: tone),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: IntrinsicHeight(
                        child: Row(
                          children: [
                            _Stat(
                              value: formatNumber(product.stock),
                              label: 'Stok sekarang',
                              color: color,
                            ),
                            const VerticalDivider(width: 1),
                            _Stat(
                              value: '${product.reorderPoint}',
                              label: 'Batas pesan\n(ROP)',
                            ),
                            const VerticalDivider(width: 1),
                            _Stat(
                              value: '${product.computedSafetyStock ?? '–'}',
                              label: 'Stok pengaman',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _OrderAdvice(product: product),
                  if (isOwner) ...[
                    const SizedBox(height: 12),
                    _WeekChart(productId: product.id),
                  ],
                  const SizedBox(height: 12),
                  Card(
                    child: Column(
                      children: [
                        _PriceRow(
                          'Harga jual',
                          formatRupiah(product.sellPrice),
                        ),
                        if (product.lastBuyPrice > 0) ...[
                          const Divider(),
                          _PriceRow(
                            'Harga beli terakhir',
                            formatRupiah(product.lastBuyPrice),
                          ),
                          const Divider(),
                          _PriceRow(
                            'Untung per pcs',
                            formatRupiah(product.profitPerUnit),
                            color: product.profitPerUnit < 0
                                ? AppColors.danger
                                : AppColors.green,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: FilledButton.icon(
                onPressed: () =>
                    context.push(Routes.warungRestockOf(product.id)),
                icon: const Icon(LucideIcons.download),
                label: const Text('Catat barang masuk'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.color});

  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: AppText.money(26, color: color ?? AppColors.ink)),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// How much to order next, and where that number comes from.
class _OrderAdvice extends StatelessWidget {
  const _OrderAdvice({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final qty = product.suggestedOrderQty;
    final pack = product.pack;
    final average = product.avgDailyTenths;
    final lead = product.leadTimeDays ?? 1;

    final String source;
    if (product.hasComputedFigures && average != null) {
      final perDay = average % 10 == 0
          ? '${average ~/ 10}'
          : '${average ~/ 10},${average % 10}';
      source =
          'Dari rata-rata terjual $perDay pcs per hari, waktu antar $lead '
          'hari.';
    } else {
      source =
          'Dari angka yang kamu isi. Dihitung otomatis setelah barang ini '
          'punya riwayat penjualan 14 hari.';
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.yellowTint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.yellow.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Saran jumlah pesan',
              style: AppText.body(
                14,
                weight: FontWeight.w600,
                color: AppColors.yellowDark,
              ),
            ),
            const SizedBox(height: 2),
            if (qty == null)
              Text('Belum ada saran', style: AppText.heading(22))
            else
              Text.rich(
                TextSpan(
                  text: '${formatNumber(qty)} pcs',
                  style: AppText.money(26),
                  children: [
                    if (pack != null && qty % pack.size == 0)
                      TextSpan(
                        text: ' (${qty ~/ pack.size} ${pack.name})',
                        style: AppText.body(
                          16,
                          weight: FontWeight.w600,
                          color: AppColors.yellowDark,
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Text(source, style: AppText.body(14)),
          ],
        ),
      ),
    );
  }
}

/// Pieces sold on each of the last seven days.
class _WeekChart extends ConsumerWidget {
  const _WeekChart({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final range = rangeFor(ReportPeriod.weekly, DateTime.now());
    final byDay =
        ref
            .watch(
              productSalesProvider((
                startKey: range.startKey,
                endKey: range.endKey,
              )),
            )
            .value ??
        const <String, Map<String, int>>{};
    final days = [
      for (final day in range.days)
        (day: day, qty: byDay[dayKeyOf(day)]?[productId] ?? 0),
    ];
    final peak = days.fold(1, (max, d) => d.qty > max ? d.qty : max);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Terjual 7 hari terakhir',
                  style: theme.textTheme.titleSmall,
                ),
                Text('pcs', style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 130,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final (index, entry) in days.indexed) ...[
                    if (index > 0) const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            '${entry.qty}',
                            style: AppText.body(
                              12,
                              weight: FontWeight.w600,
                              color: AppColors.inkMuted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            // Leaves room for the two labels around the bar.
                            height: 4 + 76 * entry.qty / peak,
                            decoration: BoxDecoration(
                              // Today stands out from the days before it.
                              color: index == days.length - 1
                                  ? AppColors.greenDark
                                  : AppColors.greenTint,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            DateFormat('E', 'id_ID').format(entry.day),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: index == days.length - 1
                                  ? FontWeight.w700
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow(this.label, this.value, {this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: AppColors.inkMuted),
          ),
          Text(
            value,
            style: AppText.body(
              16,
              weight: FontWeight.w700,
              color: color ?? AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}
