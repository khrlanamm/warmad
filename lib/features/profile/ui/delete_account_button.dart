import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../../core/firebase/function_errors.dart';
import '../../auth/data/auth_service.dart';
import '../data/profile_repository.dart';
import '../domain/user_profile.dart';

/// Lets the signed in user delete their account and its data for good.
///
/// What goes with the account depends on who they are, so the warning is
/// spelled out for each case, and they have to type a word to confirm.
class DeleteAccountButton extends ConsumerStatefulWidget {
  const DeleteAccountButton({super.key});

  @override
  ConsumerState<DeleteAccountButton> createState() =>
      _DeleteAccountButtonState();
}

class _DeleteAccountButtonState extends ConsumerState<DeleteAccountButton> {
  static const _word = 'HAPUS';
  bool _deleting = false;

  Future<void> _confirmAndDelete() async {
    final membership = ref.read(membershipProvider).value;
    final consequence = switch (membership?.role) {
      WarungRole.owner =>
        'Warung kamu ikut terhapus bersama semua barang, penjualan, catatan '
            'kas, kasbon, dan laporannya. Semua kasir kehilangan akses. '
            'Warung hilang dari peta pembeli.',
      WarungRole.cashier =>
        'Kamu keluar dari warung. Penjualan dan catatan yang sudah kamu buat '
            'tetap ada di warung itu.',
      null => 'Profil kamu sebagai pembeli terhapus.',
    };

    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Hapus akun selamanya?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(consequence),
              const SizedBox(height: 8),
              const Text('Ini tidak bisa dibatalkan.'),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'Ketik $_word'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              onPressed: controller.text.trim().toUpperCase() == _word
                  ? () => Navigator.of(context).pop(true)
                  : null,
              child: const Text('Hapus akun'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _deleting = true);
    try {
      await ref
          .read(functionsProvider)
          .httpsCallable('deleteAccount')
          .call<void>();
      // The account is gone on the server; this clears it from the phone.
      await ref.read(authServiceProvider).signOut();
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            functionErrorMessage(
              error,
              fallback: 'Gagal menghapus akun. Cek internet, lalu coba lagi.',
            ),
          ),
        ),
      );
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      style: TextButton.styleFrom(foregroundColor: AppColors.inkMuted),
      onPressed: _deleting ? null : _confirmAndDelete,
      icon: _deleting
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(LucideIcons.trash2, size: 18),
      label: Text(_deleting ? 'Menghapus akun…' : 'Hapus akun'),
    );
  }
}
