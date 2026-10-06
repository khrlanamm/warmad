import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../core/widgets/terpal_card.dart';
import '../../pos/data/sale_repository.dart';
import '../../pos/domain/sale.dart';
import '../../products/data/product_repository.dart';
import '../../products/domain/product.dart';
import '../../warung/data/warung_repository.dart';
import '../../warung/domain/cash_state.dart';

/// Beranda: the warung's cash, what is running low, and the latest sales.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static String _greeting(int hour) => switch (hour) {
    >= 4 && < 11 => 'Selamat pagi,',
    >= 11 && < 15 => 'Selamat siang,',
    >= 15 && < 18 => 'Selamat sore,',
    _ => 'Selamat malam,',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final warung = ref.watch(currentWarungProvider).value;
    final cash = ref.watch(cashStateProvider).value;
    final sales = ref.watch(recentSalesProvider).value ?? const <Sale>[];
    final low =
        (ref.watch(productsProvider).value ?? const <Product>[])
            .where((p) => p.active && p.status != StockStatus.aman)
            .toList()
          ..sort(compareByUrgency);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              _greeting(DateTime.now().hour),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.inkMuted,
              ),
            ),
            Text(warung?.name ?? '', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 16),
            _CashCard(cash: cash),
            if (low.isNotEmpty) ...[
              const SizedBox(height: 12),
              _LowStockBanner(products: low),
            ],
            const SizedBox(height: 12),
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: const Icon(LucideIcons.lock, color: AppColors.green),
                title: Text('Tutup kas', style: theme.textTheme.titleSmall),
                trailing: const Icon(LucideIcons.chevronRight),
                onTap: () => context.push(Routes.warungCashClosing),
              ),
            ),
            const SizedBox(height: 24),
            Text('Transaksi terakhir', style: theme.textTheme.titleLarge),
            const SizedBox(height: 10),
            if (sales.isEmpty)
              Text(
                'Belum ada penjualan. Catat penjualan pertama di menu Kasir.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.inkMuted,
                ),
              )
            else
              Card(
                child: Column(
                  children: [
                    for (final (index, sale) in sales.indexed) ...[
                      if (index > 0) const Divider(),
                      _SaleTile(sale: sale),
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

class _CashCard extends StatelessWidget {
  const _CashCard({required this.cash});

  final CashState? cash;

  @override
  Widget build(BuildContext context) {
    final cash = this.cash;
    final muted = AppColors.white.withValues(alpha: 0.8);
    final strong = AppText.body(
      14,
      weight: FontWeight.w700,
      color: AppColors.white,
    );

    return TerpalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Kas usaha sekarang', style: AppText.body(14, color: muted)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              cash == null ? 'Rp…' : formatRupiah(cash.expected),
              style: AppText.money(36, color: AppColors.white),
            ),
          ),
          const SizedBox(height: 14),
          Divider(color: AppColors.white.withValues(alpha: 0.25)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text.rich(
                TextSpan(
                  text: 'Penjualan ',
                  style: AppText.body(14, color: muted),
                  children: [
                    TextSpan(
                      text: formatRupiah(cash?.salesCash ?? 0),
                      style: strong,
                    ),
                  ],
                ),
              ),
              Text('${cash?.salesCount ?? 0} transaksi', style: strong),
            ],
          ),
        ],
      ),
    );
  }
}

class _LowStockBanner extends StatelessWidget {
  const _LowStockBanner({required this.products});

  /// Products that are low or out, most urgent first.
  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    final names = products.take(2).map((p) => p.name).join(', ');
    final others = products.length - 2;

    return Material(
      color: AppColors.warningTint,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.warning.withValues(alpha: 0.25)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go(Routes.warungStock),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(LucideIcons.triangleAlert, color: AppColors.warning),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${products.length} barang hampir habis',
                      style: AppText.body(
                        16,
                        weight: FontWeight.w700,
                        color: AppColors.warning,
                      ),
                    ),
                    Text(
                      others > 0 ? '$names, dan $others lainnya' : names,
                      style: AppText.body(14, color: AppColors.inkMuted),
                    ),
                  ],
                ),
              ),
              const Icon(LucideIcons.chevronRight, color: AppColors.warning),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaleTile extends StatelessWidget {
  const _SaleTile({required this.sale});

  final Sale sale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.greenTint,
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            child: Padding(
              padding: EdgeInsets.all(9),
              child: Icon(
                LucideIcons.shoppingCart,
                size: 20,
                color: AppColors.green,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Penjualan, ${sale.itemCount} barang',
                  style: theme.textTheme.bodyLarge,
                ),
                Text(
                  formatClock(sale.occurredAt),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Text(
            formatRupiah(sale.total, showPlus: true),
            style: AppText.body(
              16,
              weight: FontWeight.w700,
              color: AppColors.green,
            ),
          ),
        ],
      ),
    );
  }
}
