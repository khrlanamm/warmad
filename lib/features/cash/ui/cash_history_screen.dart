import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/date_labels.dart';
import '../../../core/money.dart';
import '../../../core/widgets/status_chip.dart';
import '../data/cash_repository.dart';
import '../domain/cash_closing.dart';

/// Riwayat tutup kas: every closing with who closed it and the difference.
class CashHistoryScreen extends ConsumerWidget {
  const CashHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final closings = ref.watch(cashClosingsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Kembali',
          onPressed: () => context.pop(),
          icon: const Icon(LucideIcons.chevronLeft),
        ),
        title: const Text('Riwayat tutup kas'),
      ),
      body: !closings.hasValue
          ? const Center(child: CircularProgressIndicator())
          : closings.value!.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Belum pernah tutup kas.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: AppColors.inkMuted,
                  ),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              itemCount: closings.value!.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) =>
                  _ClosingCard(closing: closings.value![index]),
            ),
    );
  }
}

class _ClosingCard extends StatelessWidget {
  const _ClosingCard({required this.closing});

  final CashClosing closing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final difference = closing.difference;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    formatDateTime(closing.closedAt),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                StatusChip(
                  label: difference == 0
                      ? 'Pas'
                      : 'Selisih ${formatRupiah(difference, showPlus: true)}',
                  tone: difference == 0 ? StatusTone.good : StatusTone.warning,
                ),
              ],
            ),
            Text(
              'Ditutup oleh ${closing.closedByName}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _Figure(
                    label: 'Menurut catatan',
                    amount: closing.expected,
                  ),
                ),
                Expanded(
                  child: _Figure(
                    label: 'Uang di laci',
                    amount: closing.counted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.amount});

  final String label;
  final int amount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(formatRupiah(amount), style: AppText.money(18)),
      ],
    );
  }
}
