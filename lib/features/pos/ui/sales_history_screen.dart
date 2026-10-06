import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/date_labels.dart';
import '../../../core/money.dart';
import '../../../core/widgets/status_chip.dart';
import '../../auth/data/auth_service.dart';
import '../../ledger/data/ledger_repository.dart';
import '../../ledger/domain/cash_move.dart';
import '../../profile/data/profile_repository.dart';
import '../data/sale_repository.dart';
import '../domain/sale.dart';

/// The latest 50 sales of the current warung.
final salesHistoryProvider = StreamProvider.autoDispose<List<Sale>>((ref) {
  final membership = ref.watch(membershipProvider.select((m) => m.value));
  if (membership == null) return Stream.value(const []);
  return ref
      .watch(saleRepositoryProvider)
      .watchRecent(membership.warungId, limit: 50);
});

/// Riwayat penjualan. Tapping a sale shows its items; the owner can void it.
class SalesHistoryScreen extends ConsumerWidget {
  const SalesHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sales = ref.watch(salesHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Kembali',
          onPressed: () => context.pop(),
          icon: const Icon(LucideIcons.chevronLeft),
        ),
        title: const Text('Riwayat penjualan'),
      ),
      body: !sales.hasValue
          ? const Center(child: CircularProgressIndicator())
          : sales.value!.isEmpty
          ? Center(
              child: Text(
                'Belum ada penjualan.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: AppColors.inkMuted,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              itemCount: sales.value!.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final sale = sales.value![index];
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => showSaleDetail(context, sale),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SaleSummaryRow(sale: sale, showDate: true),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// One line for a sale: what, when, how much, and whether it was kasbon or
/// has been voided.
class SaleSummaryRow extends StatelessWidget {
  const SaleSummaryRow({super.key, required this.sale, this.showDate = false});

  final Sale sale;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = sale.voided;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Penjualan, ${sale.itemCount} barang',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: muted ? AppColors.inkMuted : AppColors.ink,
                  decoration: muted ? TextDecoration.lineThrough : null,
                ),
              ),
              const SizedBox(height: 2),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    showDate
                        ? formatDateTime(sale.occurredAt)
                        : formatDateTime(sale.occurredAt).split(', ').last,
                    style: theme.textTheme.bodySmall,
                  ),
                  if (sale.voided)
                    const StatusChip(
                      label: 'Dibatalkan',
                      tone: StatusTone.danger,
                    )
                  else if (sale.onCredit)
                    StatusChip(
                      label: 'Kasbon ${sale.customerName ?? ''}'.trim(),
                      tone: StatusTone.limited,
                    ),
                ],
              ),
            ],
          ),
        ),
        Text(
          sale.onCredit
              ? formatRupiah(sale.total)
              : formatRupiah(sale.total, showPlus: true),
          style: AppText.body(
            16,
            weight: FontWeight.w700,
            color: muted || sale.onCredit
                ? AppColors.inkMuted
                : AppColors.green,
          ),
        ),
      ],
    );
  }
}

/// Opens the items of [sale] in a bottom sheet.
Future<void> showSaleDetail(BuildContext context, Sale sale) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.cream,
    builder: (context) => _SaleDetail(sale: sale),
  );
}

class _SaleDetail extends ConsumerWidget {
  const _SaleDetail({required this.sale});

  final Sale sale;

  Future<void> _void(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batalkan penjualan ini?'),
        content: Text(
          sale.onCredit
              ? 'Barang kembali ke stok dan kasbon ${sale.customerName ?? ''} '
                    'berkurang ${formatRupiah(sale.total)}. Catatan penjualan '
                    'tetap ada dengan tanda dibatalkan.'
              : 'Barang kembali ke stok dan kas berkurang '
                    '${formatRupiah(sale.total)}. Catatan penjualan tetap ada '
                    'dengan tanda dibatalkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Tidak'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Batalkan penjualan'),
          ),
        ],
      ),
    );
    final user = ref.read(authServiceProvider).currentUser;
    final warungId = ref.read(membershipProvider).value?.warungId;
    if (confirmed != true || user == null || warungId == null) return;
    if (!context.mounted) return;

    final repository = ref.read(ledgerRepositoryProvider);
    final refund = CashMove(
      id: repository.newId(warungId),
      kind: CashMoveKind.refund,
      amount: sale.total,
      cash: !sale.onCredit,
      occurredAt: DateTime.now(),
      createdByUid: user.uid,
      createdByName: user.displayName ?? user.email ?? 'Pemilik',
      saleId: sale.id,
      salePayment: sale.payment,
      customerId: sale.customerId,
      customerName: sale.customerName,
    );

    final messenger = ScaffoldMessenger.of(context);
    unawaited(
      repository.voidSale(warungId, sale, refund).catchError((Object _) {
        messenger.showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.danger,
            duration: Duration(seconds: 10),
            content: Text(
              'Pembatalan ditolak server. Mungkin penjualan ini sudah '
              'dibatalkan dari HP lain.',
            ),
          ),
        );
      }),
    );
    messenger.showSnackBar(
      const SnackBar(content: Text('Penjualan dibatalkan.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isOwner = ref.watch(membershipProvider).value?.isOwner ?? false;

    Widget line(String label, String value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: strong
                ? theme.textTheme.titleSmall
                : theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.inkMuted,
                  ),
          ),
          Text(
            value,
            style: strong
                ? AppText.money(20)
                : AppText.body(15, weight: FontWeight.w600),
          ),
        ],
      ),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Detail penjualan', style: theme.textTheme.titleLarge),
          Text(
            '${formatDateTime(sale.occurredAt)} · ${sale.cashierName}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  for (final item in sale.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${item.qty} × ${item.name}',
                              style: theme.textTheme.bodyLarge,
                            ),
                          ),
                          Text(
                            formatRupiah(item.subtotal),
                            style: AppText.body(15, weight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(),
                  ),
                  line('Total', formatRupiah(sale.total), strong: true),
                  if (sale.onCredit)
                    line('Kasbon', sale.customerName ?? '')
                  else ...[
                    line('Uang diterima', formatRupiah(sale.paid)),
                    line('Kembalian', formatRupiah(sale.change)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (sale.voided)
            const Center(
              child: StatusChip(
                label: 'Penjualan ini sudah dibatalkan',
                tone: StatusTone.danger,
              ),
            )
          else if (isOwner)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger),
              ),
              onPressed: () => _void(context, ref),
              icon: const Icon(LucideIcons.undo2),
              label: const Text('Batalkan penjualan'),
            ),
        ],
      ),
    );
  }
}
