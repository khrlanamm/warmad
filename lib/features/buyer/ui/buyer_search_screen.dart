import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/date_labels.dart';
import '../../products/data/catalog_repository.dart';
import '../data/buyer_repository.dart';
import '../domain/geo.dart';
import '../domain/public_warung.dart';
import 'buyer_widgets.dart';

/// Cari barang: pick an item, see which nearby warungs have it.
class BuyerSearchScreen extends ConsumerStatefulWidget {
  const BuyerSearchScreen({super.key});

  @override
  ConsumerState<BuyerSearchScreen> createState() => _BuyerSearchScreenState();
}

class _BuyerSearchScreenState extends ConsumerState<BuyerSearchScreen> {
  final _search = TextEditingController();
  Timer? _suggestTimer;
  List<CatalogEntry> _suggestions = const [];

  CatalogEntry? _item;
  Map<String, PublicItem>? _availability;
  bool _failed = false;
  bool _inStockOnly = false;
  bool _openOnly = false;

  @override
  void dispose() {
    _suggestTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _suggestTimer?.cancel();
    setState(() {
      _item = null;
      _availability = null;
    });
    _suggestTimer = Timer(const Duration(milliseconds: 350), () async {
      final found = await ref.read(catalogRepositoryProvider).suggest(text);
      if (mounted && _search.text == text) setState(() => _suggestions = found);
    });
  }

  Future<void> _pick(CatalogEntry entry) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _search.text = entry.name;
      _item = entry;
      _suggestions = const [];
      _availability = null;
      _failed = false;
    });
    try {
      final warungs = await ref.read(nearbyWarungsProvider.future);
      final result = await ref
          .read(buyerRepositoryProvider)
          .availability(entry.id, warungs);
      if (mounted && _item?.id == entry.id) {
        setState(() => _availability = result);
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _clear() {
    _suggestTimer?.cancel();
    _search.clear();
    setState(() {
      _item = null;
      _availability = null;
      _suggestions = const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = _item;

    return Scaffold(
      appBar: AppBar(title: const Text('Cari barang')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: TextField(
              controller: _search,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Ketik nama barang, misalnya Indomie',
                prefixIcon: const Icon(LucideIcons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Hapus pencarian',
                        onPressed: _clear,
                        icon: const Icon(LucideIcons.x),
                      ),
              ),
            ),
          ),
          Expanded(
            child: item == null
                ? _buildSuggestions(theme)
                : _buildResults(theme, item),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestions(ThemeData theme) {
    if (_suggestions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _search.text.trim().length < 2
                ? 'Ketik nama barang yang kamu cari untuk melihat warung '
                      'terdekat yang menjualnya.'
                : 'Barang tidak ditemukan. Coba kata lain.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: AppColors.inkMuted,
            ),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (index, entry) in _suggestions.indexed) ...[
                if (index > 0) const Divider(),
                ListTile(
                  title: Text(entry.name, style: theme.textTheme.bodyLarge),
                  subtitle: entry.category == null
                      ? null
                      : Text(entry.category!),
                  trailing: const Icon(LucideIcons.chevronRight),
                  onTap: () => _pick(entry),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResults(ThemeData theme, CatalogEntry item) {
    final availability = _availability;
    if (_failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Gagal memuat. Cek internet, lalu coba lagi.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _pick(item),
                child: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
      );
    }
    if (availability == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final now = DateTime.now();
    final nearby = ref.watch(nearbyWarungsProvider).value ?? const [];
    // Only warungs that carry the item at all.
    final selling = nearby.where((w) => availability.containsKey(w.id));
    final inStock = selling
        .where((w) => availability[w.id]!.status != Availability.habis)
        .length;
    final visible = selling
        .where(
          (w) =>
              !_inStockOnly || availability[w.id]!.status != Availability.habis,
        )
        .where((w) => !_openOnly || isOpenAt(w.hours, now))
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        Wrap(
          spacing: 8,
          children: [
            FilterChip(
              label: const Text('Stok tersedia'),
              selected: _inStockOnly,
              onSelected: (value) => setState(() => _inStockOnly = value),
            ),
            FilterChip(
              label: const Text('Buka sekarang'),
              selected: _openOnly,
              onSelected: (value) => setState(() => _openOnly = value),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          selling.isEmpty
              ? 'Belum ada warung terdekat yang menjual ${item.name}.'
              : 'Tersedia di $inStock dari ${selling.length} warung terdekat',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.inkMuted,
          ),
        ),
        const SizedBox(height: 10),
        for (final warung in visible) ...[
          _ResultCard(
            warung: warung,
            status: availability[warung.id]!.status,
            now: now,
          ),
          const SizedBox(height: 8),
        ],
        if (selling.isNotEmpty) ...[
          const SizedBox(height: 6),
          const AvailabilityDisclaimer(),
        ],
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.warung,
    required this.status,
    required this.now,
  });

  final PublicWarung warung;
  final Availability status;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final distance = warung.distance;
    final lastActive = warung.lastActiveAt;
    final details = [
      if (distance != null) formatDistance(distance),
      if (lastActive != null)
        'diperbarui ${formatRelativeInline(lastActive, now)}',
    ].join(' · ');

    return Opacity(
      // A warung that is out fades back, the way the design shows it.
      opacity: status == Availability.habis ? 0.55 : 1,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () =>
              context.push(Routes.buyerWarung(warung.id), extra: warung),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.greenTint,
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(LucideIcons.store, color: AppColors.green),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(warung.name, style: theme.textTheme.titleMedium),
                      Text(details, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AvailabilityChip(status),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
