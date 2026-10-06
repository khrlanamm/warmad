import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/money.dart';
import '../../../core/widgets/terpal_card.dart';
import '../../pos/data/sale_repository.dart';
import '../../pos/domain/sale.dart';
import '../../pos/ui/sales_history_screen.dart';
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
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _QuickAction(
                    icon: LucideIcons.shoppingCart,
                    label: 'Jual',
                    onTap: () => context.go(Routes.warungPos),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _QuickAction(
                    icon: LucideIcons.download,
                    label: 'Barang masuk',
                    onTap: () => context.push(Routes.warungRestock),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _QuickAction(
                    icon: LucideIcons.wallet,
                    label: 'Pengeluaran',
                    onTap: () => context.push(Routes.warungExpense),
                  ),
                ),
              ],
            ),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Transaksi terakhir', style: theme.textTheme.titleLarge),
                if (sales.isNotEmpty)
                  TextButton(
                    onPressed: () => context.push(Routes.warungSales),
                    child: const Text('Lihat semua'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if (sales.isEmpty)
              Text(
                'Belum ada penjualan. Catat penjualan pertama di menu Kasir.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.inkMuted,
                ),
              )
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (index, sale) in sales.indexed) ...[
                      if (index > 0) const Divider(),
                      InkWell(
                        onTap: () => showSaleDetail(context, sale),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: SaleSummaryRow(sale: sale),
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

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          child: Column(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.greenTint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(9),
                  child: Icon(icon, size: 22, color: AppColors.green),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: AppText.body(14, weight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
