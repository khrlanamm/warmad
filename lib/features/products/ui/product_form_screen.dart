import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/money.dart';
import '../../../core/widgets/money_field.dart';
import '../../profile/data/profile_repository.dart';
import '../data/catalog_repository.dart';
import '../data/product_repository.dart';
import '../domain/product.dart';
import 'barcode_scanner_screen.dart';

/// Adds a product, or edits the one with [productId].
class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key, this.productId});

  final String? productId;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _sellPrice = TextEditingController();
  final _buyPrice = TextEditingController();
  final _stock = TextEditingController();
  final _packName = TextEditingController();
  final _packSize = TextEditingController();
  final _rop = TextEditingController();

  String _category = productCategories.first;
  String? _barcode;
  String? _catalogId;
  Product? _editing;
  bool _saving = false;

  List<CatalogEntry> _suggestions = const [];
  Timer? _suggestTimer;

  bool get _isNew => widget.productId == null;

  @override
  void initState() {
    super.initState();
    final id = widget.productId;
    if (id == null) return;
    final product = ref
        .read(productsProvider)
        .value
        ?.where((p) => p.id == id)
        .firstOrNull;
    if (product == null) return;

    _editing = product;
    _name.text = product.name;
    _sellPrice.text = formatNumber(product.sellPrice);
    if (product.lastBuyPrice > 0) {
      _buyPrice.text = formatNumber(product.lastBuyPrice);
    }
    _packName.text = product.pack?.name ?? '';
    _packSize.text = product.pack?.size.toString() ?? '';
    _rop.text = product.manualRop?.toString() ?? '';
    _category = product.category;
    _barcode = product.barcode;
    _catalogId = product.catalogId;
  }

  @override
  void dispose() {
    _suggestTimer?.cancel();
    for (final controller in [
      _name,
      _sellPrice,
      _buyPrice,
      _stock,
      _packName,
      _packSize,
      _rop,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _onNameChanged(String text) {
    // Typing a different name means it is no longer the picked catalog item.
    _catalogId = null;
    _suggestTimer?.cancel();
    _suggestTimer = Timer(const Duration(milliseconds: 350), () async {
      final found = await ref.read(catalogRepositoryProvider).suggest(text);
      // Ignore answers for text the user has already changed.
      if (mounted && _name.text == text) setState(() => _suggestions = found);
    });
  }

  void _applyCatalogEntry(CatalogEntry entry) {
    _suggestTimer?.cancel();
    setState(() {
      _name.text = entry.name;
      _catalogId = entry.id;
      _suggestions = const [];
      if (productCategories.contains(entry.category)) {
        _category = entry.category!;
      }
      final pack = entry.pack;
      if (pack != null && pack.size > 1 && _packName.text.isEmpty) {
        _packName.text = pack.name;
        _packSize.text = pack.size.toString();
      }
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _scan() async {
    final code = await BarcodeScannerScreen.open(context);
    if (code == null || !mounted) return;

    final existing = ref
        .read(productsProvider)
        .value
        ?.where((p) => p.active && p.barcode == code && p.id != _editing?.id)
        .firstOrNull;
    if (existing != null) {
      _message('Barcode ini sudah dipakai ${existing.name}.');
      return;
    }

    setState(() => _barcode = code);
    if (_name.text.trim().isNotEmpty) return;
    final entry = await ref.read(catalogRepositoryProvider).byBarcode(code);
    if (entry != null && mounted && _name.text.trim().isEmpty) {
      _applyCatalogEntry(entry);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final warungId = ref.read(membershipProvider).value?.warungId;
    if (warungId == null) return;

    final name = _name.text.trim();
    final duplicate = ref
        .read(productsProvider)
        .value
        ?.any(
          (p) =>
              p.active &&
              p.id != _editing?.id &&
              p.name.toLowerCase() == name.toLowerCase(),
        );
    if (duplicate ?? false) {
      _message('Barang dengan nama ini sudah ada.');
      return;
    }

    final packName = _packName.text.trim();
    final packSize = int.tryParse(_packSize.text);
    final draft = ProductDraft(
      name: name,
      category: _category,
      sellPrice: parseRupiah(_sellPrice.text) ?? 0,
      lastBuyPrice: parseRupiah(_buyPrice.text) ?? 0,
      initialStock: int.tryParse(_stock.text) ?? 0,
      barcode: _barcode,
      catalogId: _catalogId,
      pack: packName.isNotEmpty && packSize != null && packSize > 0
          ? PackUnit(name: packName, size: packSize)
          : null,
      manualRop: int.tryParse(_rop.text),
      manualOrderQty: _editing?.manualOrderQty,
    );

    setState(() => _saving = true);
    try {
      final repository = ref.read(productRepositoryProvider);
      final editing = _editing;
      if (editing == null) {
        await repository.add(warungId, draft);
      } else {
        await repository.update(warungId, editing, draft);
      }
      if (mounted) context.pop();
    } catch (_) {
      if (mounted) _message('Gagal menyimpan barang. Coba lagi.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _retire() async {
    final product = _editing;
    final warungId = ref.read(membershipProvider).value?.warungId;
    if (product == null || warungId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Hapus ${product.name}?'),
        content: const Text(
          'Barang hilang dari daftar stok dan kasir. Riwayat penjualannya '
          'tetap tersimpan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref
        .read(productRepositoryProvider)
        .setActive(warungId, product.id, false);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_isNew && _editing == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Barang tidak ditemukan.')),
      );
    }
    final digits = [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(6),
    ];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Kembali',
          onPressed: () => context.pop(),
          icon: const Icon(LucideIcons.chevronLeft),
        ),
        title: Text(_isNew ? 'Tambah barang' : 'Ubah barang'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  children: [
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _scan,
                      icon: const Icon(LucideIcons.scanBarcode),
                      label: Text(
                        _barcode == null
                            ? 'Scan barcode (kalau ada)'
                            : 'Barcode $_barcode',
                      ),
                    ),
                    const _Label('Nama barang'),
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 80,
                      onChanged: _onNameChanged,
                      decoration: const InputDecoration(
                        hintText: 'Contoh: Indomie Goreng',
                        counterText: '',
                      ),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? 'Isi nama barang.'
                          : null,
                    ),
                    if (_suggestions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            for (final entry in _suggestions)
                              ListTile(
                                dense: true,
                                title: Text(
                                  entry.name,
                                  style: theme.textTheme.bodyLarge,
                                ),
                                subtitle: entry.category == null
                                    ? null
                                    : Text(entry.category!),
                                trailing: const Icon(
                                  LucideIcons.arrowUpLeft,
                                  size: 18,
                                ),
                                onTap: () => _applyCatalogEntry(entry),
                              ),
                          ],
                        ),
                      ),
                    ],
                    const _Label('Kategori'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final category in {
                          ...productCategories,
                          _category,
                        })
                          ChoiceChip(
                            label: Text(category),
                            selected: _category == category,
                            onSelected: (_) =>
                                setState(() => _category = category),
                          ),
                      ],
                    ),
                    const _Label('Harga jual per pcs'),
                    MoneyField(controller: _sellPrice, fontSize: 22),
                    const _Label('Harga beli per pcs (boleh kosong)'),
                    MoneyField(controller: _buyPrice, fontSize: 22),
                    if (_isNew) ...[
                      const _Label('Stok sekarang'),
                      TextFormField(
                        controller: _stock,
                        keyboardType: TextInputType.number,
                        inputFormatters: digits,
                        decoration: const InputDecoration(
                          hintText: '0',
                          suffixText: 'pcs',
                        ),
                      ),
                    ],
                    const _Label('Satuan beli (boleh kosong)'),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _packName,
                            maxLength: 12,
                            decoration: const InputDecoration(
                              hintText: 'dus',
                              counterText: '',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _packSize,
                            keyboardType: TextInputType.number,
                            inputFormatters: digits,
                            decoration: const InputDecoration(
                              hintText: '40',
                              prefixText: 'isi ',
                              suffixText: 'pcs',
                            ),
                            validator: (value) {
                              final hasName = _packName.text.trim().isNotEmpty;
                              final size = int.tryParse(value ?? '');
                              if (hasName && (size == null || size < 1)) {
                                return 'Isi jumlahnya.';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const _Label('Batas pesan (boleh kosong)'),
                    TextFormField(
                      controller: _rop,
                      keyboardType: TextInputType.number,
                      inputFormatters: digits,
                      decoration: const InputDecoration(
                        hintText: '0',
                        suffixText: 'pcs',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Barang ditandai hampir habis saat stok tinggal segini '
                      'atau kurang. Setelah ada riwayat penjualan, angka ini '
                      'dihitung otomatis.',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (!_isNew) ...[
                      const SizedBox(height: 24),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.danger,
                        ),
                        onPressed: _saving ? null : _retire,
                        icon: const Icon(LucideIcons.trash2),
                        label: const Text('Hapus dari daftar barang'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_isNew ? 'Simpan barang' : 'Simpan perubahan'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}
