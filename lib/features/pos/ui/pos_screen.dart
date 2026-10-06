import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/money.dart';
import '../../../core/widgets/money_field.dart';
import '../../auth/data/auth_service.dart';
import '../../products/data/product_repository.dart';
import '../../products/domain/product.dart';
import '../../products/ui/barcode_scanner_screen.dart';
import '../../profile/data/profile_repository.dart';
import '../data/sale_repository.dart';
import '../domain/cart.dart';
import '../domain/sale.dart';

/// Kasir: ring up products, take the money, show the change.
class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final _search = TextEditingController();
  final _paid = TextEditingController();
  String _query = '';
  String? _category;

  @override
  void dispose() {
    _search.dispose();
    _paid.dispose();
    super.dispose();
  }

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _change(Cart Function(Cart cart) change) {
    ref.read(cartProvider.notifier).update(change);
  }

  Future<void> _scan() async {
    final code = await BarcodeScannerScreen.open(context);
    if (code == null || !mounted) return;
    final product = ref
        .read(productsProvider)
        .value
        ?.where((p) => p.active && p.barcode == code)
        .firstOrNull;
    if (product == null) {
      _message('Barang dengan barcode ini belum terdaftar.');
      return;
    }
    _change((cart) => cart.add(product));
    _message('${product.name} ditambahkan.');
  }

  void _pay(Cart cart) {
    final user = ref.read(authServiceProvider).currentUser;
    final warungId = ref.read(membershipProvider).value?.warungId;
    if (user == null || warungId == null) return;

    // An empty field means the customer paid the exact amount.
    final paid = parseRupiah(_paid.text) ?? cart.total;
    if (paid < cart.total) return;

    final repository = ref.read(saleRepositoryProvider);
    final sale = Sale.fromCart(
      id: repository.newId(warungId),
      cart: cart,
      paid: paid,
      cashierUid: user.uid,
      cashierName: user.displayName ?? user.email ?? 'Kasir',
      now: DateTime.now(),
    );

    // Not awaited: the sale is in the local cache at once and syncs when
    // there is a connection. The till is ready for the next customer.
    final messenger = ScaffoldMessenger.of(context);
    unawaited(
      repository.record(warungId, sale).catchError((Object _) {
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: AppColors.danger,
            duration: const Duration(seconds: 10),
            content: Text(
              'Penjualan ${formatRupiah(sale.total)} ditolak server dan '
              'tidak tersimpan. Catat ulang.',
            ),
          ),
        );
      }),
    );

    ref.read(cartProvider.notifier).clear();
    _paid.clear();
    FocusScope.of(context).unfocus();
    _message(
      sale.change > 0
          ? 'Tersimpan. Kembalian ${formatRupiah(sale.change)}'
          : 'Tersimpan. Uang pas.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cart = ref.watch(cartProvider);
    final products = ref.watch(productsProvider);
    final active = (products.value ?? const <Product>[])
        .where((product) => product.active)
        .toList();

    int rank(String category) {
      final index = productCategories.indexOf(category);
      return index < 0 ? productCategories.length : index;
    }

    final categories = {for (final product in active) product.category}.toList()
      ..sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        return byRank != 0 ? byRank : a.compareTo(b);
      });
    final category = categories.contains(_category) ? _category : null;
    final visible = active
        .where((p) => category == null || p.category == category)
        .where((p) => p.matches(_query))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kasir'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton.outlined(
              tooltip: 'Scan barcode',
              onPressed: _scan,
              icon: const Icon(LucideIcons.scanBarcode),
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
              controller: _search,
              onChanged: (value) => setState(() => _query = value),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Cari barang',
                prefixIcon: const Icon(LucideIcons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Hapus pencarian',
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(LucideIcons.x),
                      ),
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
          const SizedBox(height: 8),
          Expanded(
            child: !products.hasValue
                ? const Center(child: CircularProgressIndicator())
                : visible.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        active.isEmpty
                            ? 'Belum ada barang. Tambah barang di menu Stok.'
                            : 'Tidak ada barang yang cocok.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, index) {
                      final product = visible[index];
                      return _ProductRow(
                        product: product,
                        qty: cart.qtyOf(product.id),
                        onAdd: () => _change((c) => c.add(product)),
                        onRemove: () => _change((c) => c.removeOne(product)),
                      );
                    },
                  ),
          ),
          if (!cart.isEmpty)
            _Checkout(cart: cart, paid: _paid, onPay: () => _pay(cart)),
        ],
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.product,
    required this.qty,
    required this.onAdd,
    required this.onRemove,
  });

  final Product product;
  final int qty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The sale is still allowed; the cashier just sees that the records
    // disagree with the shelf.
    final short = qty > product.stock;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    text: formatRupiah(product.sellPrice),
                    style: AppText.body(14, weight: FontWeight.w700),
                    children: [
                      TextSpan(
                        text: ' · stok ${formatNumber(product.stock)}',
                        style: AppText.body(
                          14,
                          color: short || product.stock <= 0
                              ? AppColors.danger
                              : AppColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (qty > 0) ...[
            IconButton.outlined(
              tooltip: 'Kurangi',
              onPressed: onRemove,
              icon: const Icon(LucideIcons.minus),
            ),
            SizedBox(
              width: 40,
              child: Text(
                '$qty',
                textAlign: TextAlign.center,
                style: AppText.money(20),
              ),
            ),
            IconButton.filled(
              tooltip: 'Tambah',
              onPressed: onAdd,
              icon: const Icon(LucideIcons.plus),
            ),
          ] else
            IconButton.outlined(
              tooltip: 'Tambah',
              onPressed: onAdd,
              icon: const Icon(LucideIcons.plus),
            ),
        ],
      ),
    );
  }
}

/// Total, money received, change, and the pay button.
class _Checkout extends StatefulWidget {
  const _Checkout({
    required this.cart,
    required this.paid,
    required this.onPay,
  });

  final Cart cart;
  final TextEditingController paid;
  final VoidCallback onPay;

  @override
  State<_Checkout> createState() => _CheckoutState();
}

class _CheckoutState extends State<_Checkout> {
  @override
  void initState() {
    super.initState();
    widget.paid.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.paid.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  void _setPaid(int? amount) {
    widget.paid.text = amount == null ? '' : formatNumber(amount);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = widget.cart.total;
    final typed = parseRupiah(widget.paid.text);
    final change = changeFor(total: total, paid: typed ?? total);
    final enough = change >= 0;

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${widget.cart.lineCount} jenis, '
                  '${widget.cart.itemCount} barang',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.inkMuted,
                  ),
                ),
                Text(formatRupiah(total), style: AppText.money(28)),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final option in <int?>[null, ...quickCashOptions(total)])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(
                          option == null ? 'Uang pas' : formatRupiah(option),
                        ),
                        onPressed: () => _setPaid(option),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: MoneyField(controller: widget.paid, fontSize: 20),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      enough ? 'Kembalian' : 'Kurang',
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(
                      formatRupiah(change.abs()),
                      style: AppText.money(
                        20,
                        color: enough ? AppColors.green : AppColors.danger,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: enough ? widget.onPay : null,
              child: Text('Bayar ${formatRupiah(total)}'),
            ),
          ],
        ),
      ),
    );
  }
}
