import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/firebase/function_errors.dart';
import '../../../app/theme/app_theme.dart';
import '../../profile/domain/user_profile.dart';
import '../../warung/data/warung_repository.dart';
import '../data/members_repository.dart';

/// Akun kasir: who works at the warung, inviting and removing cashiers.
class MembersScreen extends ConsumerStatefulWidget {
  const MembersScreen({super.key});

  @override
  ConsumerState<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends ConsumerState<MembersScreen> {
  bool _busy = false;

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _reason(Object error) => functionErrorMessage(error);

  Future<void> _invite() async {
    setState(() => _busy = true);
    try {
      final code = await ref.read(membersRepositoryProvider).createInvite();
      if (mounted) await _showCode(code);
    } catch (error) {
      if (mounted) _message(_reason(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showCode(String code) {
    final warungName = ref.read(currentWarungProvider).value?.name ?? 'warung';
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.cream,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Kode undangan kasir',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: SelectableText(
                    // Spaced out so it is easy to read aloud.
                    code.split('').join(' '),
                    textAlign: TextAlign.center,
                    style: AppText.money(34, color: AppColors.green),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Minta kasir masuk ke Warmad dengan akun Google-nya, pilih '
                '"Saya kasir, punya kode undangan", lalu ketik kode ini. Kode '
                'berlaku 24 jam dan hanya bisa dipakai satu kali.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => SharePlus.instance.share(
                  ShareParams(
                    text:
                        'Kode undangan kasir $warungName di Warmad: $code\n'
                        'Berlaku 24 jam, hanya untuk satu orang.',
                  ),
                ),
                icon: const Icon(LucideIcons.share2),
                label: const Text('Bagikan kode'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _remove(Member member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Keluarkan ${member.name}?'),
        content: const Text(
          'Kasir ini tidak bisa lagi membuka data warung. Catatan yang sudah '
          'dibuatnya tetap ada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Keluarkan'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(membersRepositoryProvider).remove(member.uid);
      if (mounted) _message('${member.name} sudah dikeluarkan.');
    } catch (error) {
      if (mounted) _message(_reason(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final members = ref.watch(membersProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Kembali',
          onPressed: () => context.pop(),
          icon: const Icon(LucideIcons.chevronLeft),
        ),
        title: const Text('Akun kasir'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: !members.hasValue
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                      children: [
                        Text(
                          'Kasir bisa mencatat penjualan, barang masuk, '
                          'pengeluaran, dan tutup kas. Kasir tidak bisa '
                          'mengubah barang, melihat laporan, atau mengatur '
                          'warung.',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        Card(
                          child: Column(
                            children: [
                              for (final (index, member)
                                  in members.value!.indexed) ...[
                                if (index > 0) const Divider(),
                                ListTile(
                                  title: Text(
                                    member.name,
                                    style: theme.textTheme.titleSmall,
                                  ),
                                  subtitle: Text(
                                    member.role == WarungRole.owner
                                        ? 'Pemilik'
                                        : 'Kasir',
                                  ),
                                  trailing: member.role == WarungRole.owner
                                      ? null
                                      : IconButton(
                                          tooltip: 'Keluarkan',
                                          onPressed: _busy
                                              ? null
                                              : () => _remove(member),
                                          icon: const Icon(
                                            LucideIcons.userMinus,
                                            color: AppColors.danger,
                                          ),
                                        ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: FilledButton.icon(
                onPressed: _busy ? null : _invite,
                icon: const Icon(LucideIcons.userPlus),
                label: const Text('Undang kasir'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
