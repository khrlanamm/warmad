import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/money.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../../core/widgets/money_field.dart';
import '../../auth/data/auth_service.dart';
import '../../products/data/product_repository.dart';
import '../../products/domain/product.dart';
import '../../profile/data/profile_repository.dart';
import '../../warung/data/warung_repository.dart';
import '../data/ledger_repository.dart';
import '../domain/cash_move.dart';

/// Barang masuk: record stock bought from a supplier.
class RestockScreen extends ConsumerStatefulWidget {
  const RestockScreen({super.key});

  @override
  ConsumerState<RestockScreen> createState() => _RestockScreenState();
}

class _RestockScreenState extends ConsumerState<RestockScreen> {
  final _qty = TextEditingController();
  final _unitCost = TextEditingController();

  Product? _product;
  Supplier? _supplier;
  DateTime _day = DateTime.now();
  bool _onDebt = false;

  @override
  void initState() {
    super.initState();
    _qty.addListener(_refresh);
    _unitCost.addListener(_refresh);
  }

  @override
  void dispose() {
    _qty.dispose();
    _unitCost.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  int get _quantity => int.tryParse(_qty.text) ?? 0;
  int get _total => _quantity * (parseRupiah(_unitCost.text) ?? 0);

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _pickProduct() async {
    final products = (ref.read(productsProvider).value ?? const <Product>[])
        .where((product) => product.active)
        .toList();
    final picked = await showPickerSheet<Product>(
      context,
      title: 'Pilih barang',
      items: products,
      label: (product) => product.name,
      detail: (product) => 'Stok ${formatNumber(product.stock)}',
      searchHint: 'Cari barang',
    );
    if (picked == null) return;
    setState(() {
      _product = picked;
      if (picked.lastBuyPrice > 0) {
        _unitCost.text = formatNumber(picked.lastBuyPrice);
      }
      // Start from one full pack, the way goods usually arrive.
      if (_qty.text.isEmpty && picked.pack != null) {
        _qty.text = '${picked.pack!.size}';
      }
    });
  }

  Future<void> _pickSupplier() async {
    final warungId = ref.read(membershipProvider).value?.warungId;
    if (warungId == null) return;
    final picked = await showPickerSheet<Supplier>(
      context,
      title: 'Pilih pemasok',
      items: ref.read(suppliersProvider).value ?? const [],
      label: (supplier) => supplier.name,
      searchHint: 'Cari atau ketik nama pemasok',
      onAdd: (name) => Supplier(
        id: ref.read(ledgerRepositoryProvider).addSupplier(warungId, name),
        name: name,
      ),
    );
    if (picked != null) setState(() => _supplier = picked);
  }

  void _changeQty(int delta) {
    final next = (_quantity + delta).clamp(0, 999999);
    _qty.text = next == 0 ? '' : '$next';
  }

  void _save() {
    final product = _product;
    final user = ref.read(authServiceProvider).currentUser;
    final warungId = ref.read(membershipProvider).value?.warungId;
    if (user == null || warungId == null) return;

    final unitCost = parseRupiah(_unitCost.text) ?? 0;
    if (product == null) return _message('Pilih barangnya dulu.');
    if (_quantity <= 0) return _message('Isi jumlah barang yang masuk.');
    if (unitCost <= 0) return _message('Isi harga beli per pcs.');
    if (_onDebt && _supplier == null) {
      return _message('Pilih pemasok untuk mencatat utang.');
    }

    final now = DateTime.now();
    final occurredAt = occurredAtFor(_day, now);
    final openedAt = ref.read(cashStateProvider).value?.openedAt;
    final repository = ref.read(ledgerRepositoryProvider);
    final move = CashMove(
      id: repository.newId(warungId),
      kind: CashMoveKind.purchase,
      amount: _total,
      cash: !_onDebt && countsInOpenPeriod(occurredAt, openedAt),
      occurredAt: occurredAt,
      createdByUid: user.uid,
      createdByName: user.displayName ?? user.email ?? 'Kasir',
      productId: product.id,
      productName: product.name,
      qty: _quantity,
      paidFrom: _onDebt ? 'debt' : 'cash',
      supplierId: _supplier?.id,
      supplierName: _supplier?.name,
    );

    final messenger = ScaffoldMessenger.of(context);
    unawaited(
      repository.recordPurchase(warungId, move, unitCost: unitCost).catchError((
        Object _,
      ) {
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: AppColors.danger,
            duration: const Duration(seconds: 10),
            content: Text(
              'Barang masuk ${product.name} ditolak server dan tidak '
              'tersimpan. Catat ulang.',
            ),
          ),
        );
      }),
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Tersimpan. Stok ${product.name} bertambah '
          '${formatNumber(_quantity)}.',
        ),
      ),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = _product;
    final pack = product?.pack;
    final openedAt = ref.watch(cashStateProvider).value?.openedAt;
    final backdated = !countsInOpenPeriod(
      occurredAtFor(_day, DateTime.now()),
      openedAt,
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Kembali',
          onPressed: () => context.pop(),
          icon: const Icon(LucideIcons.chevronLeft),
        ),
        title: const Text('Barang masuk'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                children: [
                  const FieldLabel('Barang'),
                  PickerField(
                    text: product?.name ?? 'Pilih barang',
                    placeholder: product == null,
                    onTap: _pickProduct,
                  ),
                  const FieldLabel('Jumlah'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              product == null
                                  ? 'Stok sekarang'
                                  : 'Stok sekarang '
                                        '${formatNumber(product.stock)}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppColors.inkMuted,
                              ),
                            ),
                          ),
                          IconButton.outlined(
                            tooltip: 'Kurangi',
                            onPressed: () => _changeQty(-1),
                            icon: const Icon(LucideIcons.minus),
                          ),
                          SizedBox(
                            width: 76,
                            child: TextField(
                              controller: _qty,
                              textAlign: TextAlign.center,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(6),
                              ],
                              style: AppText.money(22),
                              decoration: const InputDecoration(
                                hintText: '0',
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                          Text('pcs', style: theme.textTheme.bodySmall),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            tooltip: 'Tambah',
                            onPressed: () => _changeQty(1),
                            icon: const Icon(LucideIcons.plus),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (pack != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ActionChip(
                        avatar: const Icon(LucideIcons.plus, size: 16),
                        label: Text('1 ${pack.name} (${pack.size} pcs)'),
                        onPressed: () => _changeQty(pack.size),
                      ),
                    ),
                  ],
                  const FieldLabel('Harga beli per pcs'),
                  MoneyField(controller: _unitCost, fontSize: 22),
                  const FieldLabel('Pemasok'),
                  PickerField(
                    text: _supplier?.name ?? 'Pilih pemasok (boleh kosong)',
                    placeholder: _supplier == null,
                    onTap: _pickSupplier,
                  ),
                  const FieldLabel('Tanggal'),
                  DateField(
                    value: _day,
                    onChanged: (day) => setState(() => _day = day),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Lupa mencatat? Tanggal bisa diubah ke hari sebelumnya.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const FieldLabel('Dibayar dari'),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Kas usaha'),
                        selected: !_onDebt,
                        onSelected: (_) => setState(() => _onDebt = false),
                      ),
                      ChoiceChip(
                        label: const Text('Utang ke pemasok'),
                        selected: _onDebt,
                        onSelected: (_) => setState(() => _onDebt = true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.greenTint,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Total pembelian',
                                  style: theme.textTheme.titleSmall,
                                ),
                                Text(
                                  _onDebt
                                      ? 'Utang ke pemasok bertambah'
                                      : backdated
                                      ? 'Sebelum tutup kas terakhir, kas '
                                            'sekarang tidak berubah'
                                      : 'Kas usaha berkurang',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Text(
                            formatRupiah(_total),
                            style: AppText.money(
                              22,
                              color: AppColors.greenDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: FilledButton(
                onPressed: _save,
                child: const Text('Simpan barang masuk'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
