import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/money.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../../core/widgets/money_field.dart';
import '../../auth/data/auth_service.dart';
import '../../profile/data/profile_repository.dart';
import '../../warung/data/warung_repository.dart';
import '../data/ledger_repository.dart';
import '../domain/cash_move.dart';

/// Catat pengeluaran: a business expense, or money taken for personal use
/// (prive). The two are kept apart so the business cash stays clear.
class ExpenseScreen extends ConsumerStatefulWidget {
  const ExpenseScreen({super.key});

  @override
  ConsumerState<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends ConsumerState<ExpenseScreen> {
  final _amount = TextEditingController();
  final _note = TextEditingController();

  bool _personal = false;
  String _category = expenseCategories.first;
  DateTime _day = DateTime.now();
  int? _value;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final user = ref.read(authServiceProvider).currentUser;
    final warungId = ref.read(membershipProvider).value?.warungId;
    final amount = _value ?? 0;
    if (user == null || warungId == null) return;
    if (amount <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Isi nominalnya dulu.')));
      return;
    }

    final occurredAt = occurredAtFor(_day, DateTime.now());
    final openedAt = ref.read(cashStateProvider).value?.openedAt;
    final repository = ref.read(ledgerRepositoryProvider);
    final move = CashMove(
      id: repository.newId(warungId),
      kind: _personal ? CashMoveKind.prive : CashMoveKind.expense,
      amount: amount,
      cash: countsInOpenPeriod(occurredAt, openedAt),
      occurredAt: occurredAt,
      createdByUid: user.uid,
      createdByName: user.displayName ?? user.email ?? 'Kasir',
      category: _personal ? 'Pribadi' : _category,
      note: _note.text.trim(),
    );

    final messenger = ScaffoldMessenger.of(context);
    unawaited(
      repository.recordExpense(warungId, move).catchError((Object _) {
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: AppColors.danger,
            duration: const Duration(seconds: 10),
            content: Text(
              'Pengeluaran ${formatRupiah(amount)} ditolak server dan tidak '
              'tersimpan. Catat ulang.',
            ),
          ),
        );
      }),
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          _personal
              ? 'Tersimpan sebagai pengambilan pribadi.'
              : 'Pengeluaran tersimpan.',
        ),
      ),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cash = ref.watch(cashStateProvider).value;
    final counts = countsInOpenPeriod(
      occurredAtFor(_day, DateTime.now()),
      cash?.openedAt,
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Kembali',
          onPressed: () => context.pop(),
          icon: const Icon(LucideIcons.chevronLeft),
        ),
        title: const Text('Catat pengeluaran'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                children: [
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: false, label: Text('Untuk usaha')),
                      ButtonSegment(value: true, label: Text('Untuk pribadi')),
                    ],
                    selected: {_personal},
                    onSelectionChanged: (selection) =>
                        setState(() => _personal = selection.first),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _personal
                        ? 'Uang yang diambil untuk keperluan pribadi (prive). '
                              'Kas di laci berkurang, tapi tidak dihitung '
                              'sebagai biaya usaha.'
                        : 'Biaya untuk menjalankan warung, misalnya listrik '
                              'atau plastik. Uang untuk keperluan pribadi '
                              'dicatat terpisah di "Untuk pribadi".',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (!_personal) ...[
                    const FieldLabel('Kategori'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final category in expenseCategories)
                          ChoiceChip(
                            label: Text(category),
                            selected: _category == category,
                            onSelected: (_) =>
                                setState(() => _category = category),
                          ),
                      ],
                    ),
                  ],
                  const FieldLabel('Nominal'),
                  MoneyField(
                    controller: _amount,
                    fontSize: 30,
                    onChanged: (value) => setState(() => _value = value),
                  ),
                  const FieldLabel('Catatan (boleh kosong)'),
                  TextField(
                    controller: _note,
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: 100,
                    decoration: InputDecoration(
                      hintText: _personal
                          ? 'Contoh: belanja dapur'
                          : 'Contoh: kantong plastik 2 pak',
                      counterText: '',
                    ),
                  ),
                  const FieldLabel('Tanggal'),
                  DateField(
                    value: _day,
                    onChanged: (day) => setState(() => _day = day),
                  ),
                  const SizedBox(height: 16),
                  if (cash != null)
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
                              child: Text(
                                counts
                                    ? 'Kas usaha setelah dicatat'
                                    : 'Sebelum tutup kas terakhir, kas '
                                          'sekarang tidak berubah',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                            Text(
                              formatRupiah(
                                cash.expected - (counts ? (_value ?? 0) : 0),
                              ),
                              style: AppText.money(
                                20,
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
                child: const Text('Simpan pengeluaran'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
