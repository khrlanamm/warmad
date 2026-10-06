import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/money.dart';
import '../../../core/widgets/terpal_card.dart';
import '../../warung/data/warung_repository.dart';
import '../../warung/domain/cash_state.dart';

/// Beranda: the warung's cash at a glance.
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
                      style: AppText.body(
                        14,
                        weight: FontWeight.w700,
                        color: AppColors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${cash?.salesCount ?? 0} transaksi',
                style: AppText.body(
                  14,
                  weight: FontWeight.w700,
                  color: AppColors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
