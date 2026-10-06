import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/money.dart';
import '../../../core/widgets/status_chip.dart';
import '../../profile/data/profile_repository.dart';
import '../data/product_repository.dart';
import '../domain/product.dart';

/// Stok barang: every product with its remaining stock and status.
class StockListScreen extends ConsumerStatefulWidget {
  const StockListScreen({super.key});

  @override
  ConsumerState<StockListScreen> createState() => _StockListScreenState();
}

class _StockListScreenState extends ConsumerState<StockListScreen> {
  String _query = '';
  String? _category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOwner = ref.watch(membershipProvider).value?.isOwner ?? false;
    final products = ref.watch(productsProvider);
    final active = (products.value ?? const <Product>[])
        .where((product) => product.active)
        .toList();

    // Known categories keep their usual order; custom ones follow by name.
    int rank(String category) {
      final index = productCategories.indexOf(category);
      return index < 0 ? productCategories.length : index;
    }

    final categories = {for (final product in active) product.category}.toList()
      ..sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        return byRank != 0 ? byRank : a.compareTo(b);
      });
    // A category can disappear when its last product is retired.
    final category = categories.contains(_category) ? _category : null;

    final visible =
        active
            .where((p) => category == null || p.category == category)
            .where((p) => p.matches(_query))
            .toList()
          ..sort(compareByUrgency);

    final low = active.where((p) => p.status == StockStatus.hampirHabis).length;
    final out = active.where((p) => p.status == StockStatus.habis).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stok barang'),
        actions: [
          if (isOwner)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: IconButton.filled(
                tooltip: 'Tambah barang',
                onPressed: () => context.push(Routes.warungProductNew),
                icon: const Icon(LucideIcons.plus),
              ),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Cari barang',
                prefixIcon: Icon(LucideIcons.search),
              ),
            ),
          ),
          if (categories.length > 1)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  for (final option in [null, ...categories])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(option ?? 'Semua'),
                        selected: category == option,
                        onSelected: (_) => setState(() => _category = option),
                      ),
                    ),
                ],
              ),
            ),
          if (active.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text.rich(
                TextSpan(
                  text: '${formatNumber(active.length)} barang',
                  children: [
                    if (low > 0)
                      TextSpan(
                        text: ', $low hampir habis',
                        style: const TextStyle(color: AppColors.warning),
                      ),
                    if (out > 0)
                      TextSpan(
                        text: ', $out habis',
                        style: const TextStyle(color: AppColors.danger),
                      ),
                  ],
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          Expanded(
            child: !products.hasValue
                ? const Center(child: CircularProgressIndicator())
                : active.isEmpty
                ? _EmptyState(isOwner: isOwner)
                : visible.isEmpty
                ? Center(
                    child: Text(
                      'Tidak ada barang yang cocok.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: AppColors.inkMuted,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final product = visible[index];
                      return _ProductTile(
                        product: product,
                        onTap: isOwner
                            ? () =>
                                  context.push(Routes.warungProduct(product.id))
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, this.onTap});

  final Product product;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, tone, color) = switch (product.status) {
      StockStatus.habis => ('Habis', StatusTone.danger, AppColors.danger),
      StockStatus.hampirHabis => (
        'Hampir habis',
        StatusTone.warning,
        AppColors.warning,
      ),
      StockStatus.aman => ('Aman', StatusTone.good, AppColors.ink),
    };
    final details = [
      product.category,
      if (product.reorderPoint > 0) 'batas pesan ${product.reorderPoint}',
    ].join(' · ');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(details, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatNumber(product.stock),
                    style: AppText.money(22, color: color),
                  ),
                  const SizedBox(height: 4),
                  StatusChip(label: label, tone: tone),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isOwner});

  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.package, size: 48, color: AppColors.border),
            const SizedBox(height: 12),
            Text('Belum ada barang', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              isOwner
                  ? 'Tambah barang yang dijual supaya bisa mulai mencatat '
                        'penjualan.'
                  : 'Pemilik warung belum menambahkan barang.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.inkMuted,
              ),
            ),
            if (isOwner) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => context.push(Routes.warungProductNew),
                icon: const Icon(LucideIcons.plus),
                label: const Text('Tambah barang'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
