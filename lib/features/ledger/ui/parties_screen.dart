import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/money.dart';
import '../../../core/widgets/money_field.dart';
import '../../auth/data/auth_service.dart';
import '../../profile/data/profile_repository.dart';
import '../data/ledger_repository.dart';
import '../domain/cash_move.dart';

/// Asks for a name and returns it trimmed, or null when cancelled.
Future<String?> _askName(BuildContext context, String title, String hint) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        maxLength: 60,
        decoration: InputDecoration(hintText: hint, counterText: ''),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        TextButton(
          onPressed: () {
            final name = controller.text.trim();
            Navigator.of(context).pop(name.isEmpty ? null : name);
          },
          child: const Text('Simpan'),
        ),
      ],
    ),
  );
}

/// Asks how much is being paid, starting from the full [owed] amount.
Future<int?> _askAmount(
  BuildContext context, {
  required String title,
  required String body,
  required int owed,
}) {
  final controller = TextEditingController(text: formatNumber(owed));
  return showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(body),
          const SizedBox(height: 12),
          MoneyField(controller: controller, fontSize: 22, autofocus: true),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        TextButton(
          onPressed: () {
            final amount = parseRupiah(controller.text) ?? 0;
            // Paying more than is owed is almost always a typing slip.
            Navigator.of(context)
                .pop(amount > 0 && amount <= owed ? amount : null);
          },
          child: const Text('Simpan'),
        ),
      ],
    ),
  );
}

class _PartyList extends StatelessWidget {
  const _PartyList({
    required this.title,
    required this.emptyText,
    required this.addTooltip,
    required this.onAdd,
    required this.loading,
    required this.rows,
  });

  final String title;
  final String emptyText;
  final String addTooltip;
  final VoidCallback onAdd;
  final bool loading;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Kembali',
          onPressed: () => context.pop(),
          icon: const Icon(LucideIcons.chevronLeft),
        ),
        title: Text(title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton.filled(
              tooltip: addTooltip,
              onPressed: onAdd,
              icon: const Icon(LucideIcons.plus),
            ),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : rows.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  emptyText,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: AppColors.inkMuted,
                  ),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, index) => rows[index],
            ),
    );
  }
}

class _PartyTile extends StatelessWidget {
  const _PartyTile({
    required this.name,
    required this.owed,
    required this.owedLabel,
    required this.actionLabel,
    required this.onAction,
  });

  final String name;
  final int owed;
  final String owedLabel;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  if (owed > 0)
                    Text.rich(
                      TextSpan(
                        text: '$owedLabel ',
                        style: theme.textTheme.bodySmall,
                        children: [
                          TextSpan(
                            text: formatRupiah(owed),
                            style: AppText.body(
                              14,
                              weight: FontWeight.w700,
                              color: AppColors.warning,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Text('Lunas', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            if (owed > 0)
              TextButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

/// Pemasok: suppliers and what the warung owes them.
class SuppliersScreen extends ConsumerWidget {
  const SuppliersScreen({super.key});

  Future<void> _pay(
    BuildContext context,
    WidgetRef ref,
    Supplier supplier,
  ) async {
    final amount = await _askAmount(
      context,
      title: 'Bayar utang',
      body: 'Dibayar dari kas usaha ke ${supplier.name}.',
      owed: supplier.debt,
    );
    final user = ref.read(authServiceProvider).currentUser;
    final warungId = ref.read(membershipProvider).value?.warungId;
    if (amount == null || user == null || warungId == null) return;

    final repository = ref.read(ledgerRepositoryProvider);
    unawaited(
      repository.recordSupplierPayment(
        warungId,
        CashMove(
          id: repository.newId(warungId),
          kind: CashMoveKind.supplierPayment,
          amount: amount,
          cash: true,
          occurredAt: DateTime.now(),
          createdByUid: user.uid,
          createdByName: user.displayName ?? user.email ?? 'Kasir',
          supplierId: supplier.id,
          supplierName: supplier.name,
        ),
      ),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tersimpan. Utang ke ${supplier.name} berkurang '
            '${formatRupiah(amount)}.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliers = ref.watch(suppliersProvider);
    return _PartyList(
      title: 'Pemasok',
      emptyText:
          'Belum ada pemasok. Tambahkan di sini atau saat mencatat barang '
          'masuk.',
      addTooltip: 'Tambah pemasok',
      loading: !suppliers.hasValue,
      onAdd: () async {
        final name = await _askName(context, 'Tambah pemasok', 'Nama pemasok');
        final warungId = ref.read(membershipProvider).value?.warungId;
        if (name == null || warungId == null) return;
        ref.read(ledgerRepositoryProvider).addSupplier(warungId, name);
      },
      rows: [
        for (final supplier in suppliers.value ?? const <Supplier>[])
          _PartyTile(
            name: supplier.name,
            owed: supplier.debt,
            owedLabel: 'Utang',
            actionLabel: 'Bayar',
            onAction: () => _pay(context, ref, supplier),
          ),
      ],
    );
  }
}

/// Kasbon: customers who bought on credit and what they still owe.
class CustomersScreen extends ConsumerWidget {
  const CustomersScreen({super.key});

  Future<void> _collect(
    BuildContext context,
    WidgetRef ref,
    Customer customer,
  ) async {
    final amount = await _askAmount(
      context,
      title: 'Terima pembayaran',
      body: 'Uang dari ${customer.name} masuk ke kas usaha.',
      owed: customer.balance,
    );
    final user = ref.read(authServiceProvider).currentUser;
    final warungId = ref.read(membershipProvider).value?.warungId;
    if (amount == null || user == null || warungId == null) return;

    final repository = ref.read(ledgerRepositoryProvider);
    unawaited(
      repository.recordDebtPayment(
        warungId,
        CashMove(
          id: repository.newId(warungId),
          kind: CashMoveKind.debtPayment,
          amount: amount,
          cash: true,
          occurredAt: DateTime.now(),
          createdByUid: user.uid,
          createdByName: user.displayName ?? user.email ?? 'Kasir',
          customerId: customer.id,
          customerName: customer.name,
        ),
      ),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tersimpan. Kasbon ${customer.name} berkurang '
            '${formatRupiah(amount)}.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customers = ref.watch(customersProvider);
    return _PartyList(
      title: 'Kasbon pelanggan',
      emptyText:
          'Belum ada kasbon. Pilih "Kasbon" di kasir saat pelanggan bayar '
          'nanti.',
      addTooltip: 'Tambah pelanggan',
      loading: !customers.hasValue,
      onAdd: () async {
        final name = await _askName(
          context,
          'Tambah pelanggan',
          'Nama pelanggan',
        );
        final warungId = ref.read(membershipProvider).value?.warungId;
        if (name == null || warungId == null) return;
        ref.read(ledgerRepositoryProvider).addCustomer(warungId, name);
      },
      rows: [
        for (final customer in customers.value ?? const <Customer>[])
          _PartyTile(
            name: customer.name,
            owed: customer.balance,
            owedLabel: 'Kasbon',
            actionLabel: 'Terima bayar',
            onAction: () => _collect(context, ref, customer),
          ),
      ],
    );
  }
}
