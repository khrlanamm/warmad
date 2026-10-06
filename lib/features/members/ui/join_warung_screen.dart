import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router.dart';
import '../../../core/firebase/function_errors.dart';
import '../../../app/theme/app_theme.dart';
import '../../auth/data/auth_service.dart';
import '../../profile/data/profile_repository.dart';
import '../data/members_repository.dart';

/// Lets a cashier join a warung with the code the owner gave them.
class JoinWarungScreen extends ConsumerStatefulWidget {
  const JoinWarungScreen({super.key});

  @override
  ConsumerState<JoinWarungScreen> createState() => _JoinWarungScreenState();
}

class _JoinWarungScreenState extends ConsumerState<JoinWarungScreen> {
  final _code = TextEditingController();
  bool _joining = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _joining = true);
    try {
      final warungName = await ref
          .read(membersRepositoryProvider)
          .acceptInvite(_code.text, ref.read(authServiceProvider));
      // The router moves on to the warung once the new membership is known.
      ref.invalidate(membershipByUidProvider);
      messenger.showSnackBar(
        SnackBar(content: Text('Berhasil bergabung dengan $warungName.')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            functionErrorMessage(
              error,
              fallback: 'Gagal bergabung. Cek internet, lalu coba lagi.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Kembali',
          onPressed: _joining ? null : () => context.go(Routes.role),
          icon: const Icon(LucideIcons.chevronLeft),
        ),
        title: const Text('Gabung sebagai kasir'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Ketik kode undangan dari pemilik warung.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _code,
                autofocus: true,
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enableSuggestions: false,
                style: AppText.money(32),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
                  LengthLimitingTextInputFormatter(6),
                  TextInputFormatter.withFunction(
                    (_, value) =>
                        value.copyWith(text: value.text.toUpperCase()),
                  ),
                ],
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'ABC234'),
              ),
              const SizedBox(height: 10),
              Text(
                'Kode terdiri dari 6 huruf atau angka dan berlaku 24 jam. '
                'Belum punya? Minta pemilik membuka Akun > Akun kasir > Undang '
                'kasir.',
                style: theme.textTheme.bodySmall,
              ),
              const Spacer(),
              FilledButton(
                onPressed: _joining || _code.text.length != 6 ? null : _join,
                child: _joining
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Text('Gabung'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
