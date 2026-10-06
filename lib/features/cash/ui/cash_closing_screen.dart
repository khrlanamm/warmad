import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/date_labels.dart';
import '../../../core/money.dart';
import '../../../core/widgets/money_field.dart';
import '../../auth/data/auth_service.dart';
import '../../profile/data/profile_repository.dart';
import '../../warung/data/warung_repository.dart';
import '../../warung/domain/cash_state.dart';
import '../data/cash_repository.dart';
import '../domain/cash_closing.dart';

/// Tutup kas: compare the cash on record with the cash in the drawer and
/// close the period.
class CashClosingScreen extends ConsumerStatefulWidget {
  const CashClosingScreen({super.key});

  @override
  ConsumerState<CashClosingScreen> createState() => _CashClosingScreenState();
}

class _CashClosingScreenState extends ConsumerState<CashClosingScreen> {
  final _counted = TextEditingController();
  int? _amount;

  @override
  void dispose() {
    _counted.dispose();
    super.dispose();
  }

  void _close(CashState cash, int counted) {
    final user = ref.read(authServiceProvider).currentUser;
    final warungId = ref.read(membershipProvider).value?.warungId;
    if (user == null || warungId == null) return;

    final closing = CashClosing.of(
      cash,
      counted: counted,
      closedByUid: user.uid,
      closedByName: user.displayName ?? user.email ?? 'Kasir',
      now: DateTime.now(),
    );

    // Not awaited, so closing works offline. The server only refuses when
    // another phone closed this period first.
    final messenger = ScaffoldMessenger.of(context);
    unawaited(
      ref.read(cashRepositoryProvider).close(warungId, closing).catchError((
        Object _,
      ) {
        messenger.showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.danger,
            duration: Duration(seconds: 10),
            content: Text(
              'Tutup kas ditolak: periode ini sudah ditutup dari HP lain. '
              'Cek riwayat tutup kas.',
            ),
          ),
        );
      }),
    );

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Kas ditutup. Saldo awal berikutnya ${formatRupiah(counted)}.',
        ),
      ),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cash = ref.watch(cashStateProvider).value;
    final lateRecords =
        ref.watch(lateRecordsProvider).value ?? (count: 0, net: 0);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Kembali',
          onPressed: () => context.pop(),
          icon: const Icon(LucideIcons.chevronLeft),
        ),
        title: const Text('Tutup kas'),
      ),
      body: cash == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  Text(
                    formatLongDate(DateTime.now()),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.inkMuted,
                    ),
                  ),
                  if (cash.openedAt != null)
                    Text(
                      'Periode sejak ${formatDateTime(cash.openedAt!)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  const SizedBox(height: 14),
                  _Summary(cash: cash),
                  if (lateRecords.count > 0) ...[
                    const SizedBox(height: 10),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.yellowTint,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          '${lateRecords.count} penjualan '
                          '(${formatRupiah(lateRecords.net)}) '
                          'dicatat sebelum tutup kas terakhir, tapi baru masuk '
                          'sesudahnya karena HP-nya sedang tanpa internet. '
                          'Uangnya sudah ikut terhitung waktu itu, jadi kas '
                          'sekarang bisa tampak kurang '
                          '${formatRupiah(lateRecords.net)}.',
                          style: AppText.body(14),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    'Hitung uang di laci, lalu isi di sini',
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  MoneyField(
                    controller: _counted,
                    fontSize: 30,
                    onChanged: (value) => setState(() => _amount = value),
                  ),
                  if (_amount != null) ...[
                    const SizedBox(height: 14),
                    _Difference(difference: cash.differenceFor(_amount!)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _amount == null
                        ? null
                        : () => _close(cash, _amount!),
                    child: const Text('Simpan dan tutup kas'),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () => context.pop(),
                    child: const Text('Cek lagi nanti'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.cash});

  final CashState cash;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget row(String label, int amount, {int sign = 0}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: AppColors.inkMuted,
              ),
            ),
            Text(
              sign == 0
                  ? formatRupiah(amount)
                  : formatRupiah(sign * amount, showPlus: true),
              style: AppText.body(
                16,
                weight: FontWeight.w700,
                color: switch (sign) {
                  > 0 => AppColors.green,
                  < 0 => AppColors.danger,
                  _ => AppColors.ink,
                },
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Column(
          children: [
            row('Saldo awal', cash.openingBalance),
            row('Penjualan tunai', cash.salesCash, sign: 1),
            // Lines that are zero are left out to keep the list short.
            if (cash.debtCollected > 0)
              row('Kasbon dibayar', cash.debtCollected, sign: 1),
            if (cash.purchasesCash > 0)
              row('Pembelian barang', cash.purchasesCash, sign: -1),
            if (cash.expenses > 0)
              row('Pengeluaran usaha', cash.expenses, sign: -1),
            if (cash.prive > 0)
              row('Diambil untuk pribadi', cash.prive, sign: -1),
            if (cash.refunds > 0)
              row('Penjualan dibatalkan', cash.refunds, sign: -1),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Kas menurut catatan', style: theme.textTheme.titleSmall),
                Text(formatRupiah(cash.expected), style: AppText.money(22)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Difference extends StatelessWidget {
  const _Difference({required this.difference});

  final int difference;

  @override
  Widget build(BuildContext context) {
    final (title, body, color, background, icon) = switch (difference) {
      0 => (
        'Pas, tidak ada selisih',
        'Uang di laci sama dengan catatan.',
        AppColors.green,
        AppColors.greenTint,
        LucideIcons.circleCheck,
      ),
      < 0 => (
        'Selisih ${formatRupiah(difference)}',
        'Uang di laci kurang dari catatan. Cek penjualan atau pengeluaran '
            'yang belum dicatat. Kas tetap bisa ditutup.',
        AppColors.warning,
        AppColors.warningTint,
        LucideIcons.triangleAlert,
      ),
      _ => (
        'Selisih ${formatRupiah(difference, showPlus: true)}',
        'Uang di laci lebih dari catatan. Mungkin ada penjualan yang belum '
            'dicatat. Kas tetap bisa ditutup.',
        AppColors.warning,
        AppColors.warningTint,
        LucideIcons.triangleAlert,
      ),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.heading(20, color: color)),
                  const SizedBox(height: 4),
                  Text(body, style: AppText.body(14)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
