import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/warmad_logo.dart';
import '../../auth/data/auth_service.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/domain/user_profile.dart';

/// First screen after sign in: pick the side of the app to use.
class RoleSelectionScreen extends ConsumerStatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  ConsumerState<RoleSelectionScreen> createState() =>
      _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends ConsumerState<RoleSelectionScreen> {
  AppMode _selected = AppMode.warung;
  bool _saving = false;

  Future<void> _continue() async {
    final auth = ref.read(authServiceProvider);
    final user = auth.currentUser;
    if (user == null) return;

    setState(() => _saving = true);
    try {
      final existing = ref.read(userProfileProvider).value;
      await ref
          .read(profileRepositoryProvider)
          .setMode(user, _selected, isNew: existing == null);
      // The router allows an owner without a warung to stay here (to change
      // role), so moving on to registration has to be explicit.
      if (mounted && _selected == AppMode.warung) {
        context.go(Routes.warungSetup);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal menyimpan. Coba lagi.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: WarmadLogo(width: 130)),
              const SizedBox(height: 36),
              Text(
                'Mau pakai Warmad sebagai apa?',
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 20),
              _RoleCard(
                icon: LucideIcons.store,
                title: 'Saya pemilik warung',
                description:
                    'Catat stok, kasir, dan kas usaha dalam satu aplikasi.',
                selected: _selected == AppMode.warung,
                onTap: () => setState(() => _selected = AppMode.warung),
              ),
              const SizedBox(height: 12),
              _RoleCard(
                icon: LucideIcons.mapPin,
                title: 'Saya pembeli',
                description:
                    'Cari warung terdekat dan cek barang yang tersedia.',
                selected: _selected == AppMode.pembeli,
                onTap: () => setState(() => _selected = AppMode.pembeli),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _saving ? null : _continue,
                child: const Text('Lanjut'),
              ),
              const SizedBox(height: 4),
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

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: AppColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? AppColors.green : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: selected ? AppColors.green : AppColors.greenTint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Icon(
                      icon,
                      color: selected ? AppColors.white : AppColors.green,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected ? LucideIcons.circleCheck : LucideIcons.circle,
                  color: selected ? AppColors.green : AppColors.border,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
