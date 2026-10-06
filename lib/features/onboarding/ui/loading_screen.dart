import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/warmad_logo.dart';
import '../../auth/data/auth_service.dart';
import '../../profile/data/profile_repository.dart';

/// Shown while the profile and membership of the signed in user load.
class LoadingScreen extends ConsumerStatefulWidget {
  const LoadingScreen({super.key});

  @override
  ConsumerState<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends ConsumerState<LoadingScreen> {
  // A brand new account cannot be loaded without a connection, so say so
  // instead of spinning forever.
  late final Timer _slowTimer = Timer(const Duration(seconds: 8), () {
    if (mounted) setState(() => _slow = true);
  });
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _slowTimer; // Start the timer.
  }

  @override
  void dispose() {
    _slowTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed =
        ref.watch(userProfileProvider).hasError ||
        ref.watch(membershipProvider).hasError;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const WarmadLogo(width: 150),
              const SizedBox(height: 32),
              if (!failed) ...[
                const CircularProgressIndicator(),
                if (_slow) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Masih memuat. Cek koneksi internet.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.inkMuted,
                    ),
                  ),
                ],
              ] else ...[
                Text(
                  'Gagal memuat akun. Cek internet, lalu coba lagi.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    ref.invalidate(profileByUidProvider);
                    ref.invalidate(membershipByUidProvider);
                  },
                  child: const Text('Coba lagi'),
                ),
              ],
              if (failed || _slow)
                TextButton(
                  onPressed: () => ref.read(authServiceProvider).signOut(),
                  child: const Text('Keluar akun'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
