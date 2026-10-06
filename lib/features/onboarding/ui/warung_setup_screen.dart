import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router.dart';
import '../../../core/firebase/function_errors.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/location/location_service.dart';
import '../../../core/money.dart';
import '../../../core/widgets/money_field.dart';
import '../../auth/data/auth_service.dart';
import '../../profile/data/profile_repository.dart';
import '../../warung/data/warung_repository.dart';
import '../../warung/domain/warung.dart';
import 'location_picker.dart';

/// Registers the owner's warung in two steps: the warung itself, then the
/// starting cash and whether buyers may see it on the map.
class WarungSetupScreen extends ConsumerStatefulWidget {
  const WarungSetupScreen({super.key});

  @override
  ConsumerState<WarungSetupScreen> createState() => _WarungSetupScreenState();
}

class _WarungSetupScreenState extends ConsumerState<WarungSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _balance = TextEditingController();

  int _step = 0;
  Coordinates? _location;
  bool _is24h = true;
  TimeOfDay _open = const TimeOfDay(hour: 6, minute: 0);
  TimeOfDay _close = const TimeOfDay(hour: 22, minute: 0);
  bool _showOnMap = false;
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _balance.dispose();
    super.dispose();
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _next() {
    if (!_formKey.currentState!.validate()) return;
    if (_location == null) {
      _message('Geser peta dulu sampai pin ada di lokasi warung.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _step = 1);
  }

  void _back() {
    if (_step == 1) {
      setState(() => _step = 0);
    } else {
      context.go(Routes.role);
    }
  }

  Future<void> _pickTime({required bool opening}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: opening ? _open : _close,
      helpText: opening ? 'Jam buka' : 'Jam tutup',
    );
    if (picked == null) return;
    setState(() => opening ? _open = picked : _close = picked);
  }

  static String _hhmm(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    final location = _location;
    if (location == null) return;

    setState(() => _submitting = true);
    try {
      await ref
          .read(warungRepositoryProvider)
          .create(
            NewWarung(
              name: _name.text.trim(),
              phone: _phone.text.trim(),
              address: _address.text.trim(),
              lat: location.lat,
              lng: location.lng,
              hours: _is24h
                  ? const OpeningHours.allDay()
                  : OpeningHours.custom(
                      open: _hhmm(_open),
                      close: _hhmm(_close),
                    ),
              showOnMap: _showOnMap,
              openingBalance: parseRupiah(_balance.text) ?? 0,
            ),
            ref.read(authServiceProvider),
          );
      // The router moves on to the warung once the new membership is known.
      ref.invalidate(membershipByUidProvider);
    } catch (error) {
      if (!mounted) return;
      _message(
        functionErrorMessage(
          error,
          fallback: 'Gagal mendaftarkan warung. Cek internet, lalu coba lagi.',
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_submitting) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: _submitting ? null : _back,
            tooltip: 'Kembali',
            icon: const Icon(LucideIcons.chevronLeft),
          ),
          title: const Text('Daftar warung'),
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        for (var i = 0; i < 2; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          Expanded(
                            child: Container(
                              height: 6,
                              decoration: BoxDecoration(
                                color: i <= _step
                                    ? AppColors.green
                                    : AppColors.border,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _step == 0
                          ? 'Langkah 1 dari 2: data warung'
                          : 'Langkah 2 dari 2: kas dan peta',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Expanded(
                // Both steps stay mounted so the form keeps what was typed.
                child: IndexedStack(
                  index: _step,
                  children: [_buildDetails(theme), _buildCashAndMap(theme)],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: FilledButton(
                  onPressed: _submitting
                      ? null
                      : (_step == 0 ? _next : _submit),
                  child: _submitting
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : Text(_step == 0 ? 'Lanjut' : 'Buat warung'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetails(ThemeData theme) {
    String? required(String? value, String message) =>
        (value == null || value.trim().isEmpty) ? message : null;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        children: [
          const _Label('Nama warung'),
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            maxLength: 60,
            decoration: const InputDecoration(
              hintText: 'Contoh: Warung Barokah',
              counterText: '',
            ),
            validator: (v) => required(v, 'Isi nama warung.'),
          ),
          const _Label('Nomor HP'),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
              LengthLimitingTextInputFormatter(18),
            ],
            decoration: const InputDecoration(hintText: '0812 3456 7890'),
            validator: (v) {
              final digits = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
              return digits.length < 8 || digits.length > 15
                  ? 'Isi nomor HP yang benar.'
                  : null;
            },
          ),
          const _Label('Alamat'),
          TextFormField(
            controller: _address,
            textCapitalization: TextCapitalization.words,
            maxLength: 200,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Nama jalan, nomor, desa atau kelurahan',
              counterText: '',
            ),
            validator: (v) => required(v, 'Isi alamat warung.'),
          ),
          const _Label('Lokasi warung'),
          LocationPicker(onChanged: (value) => _location = value),
          const _Label('Jam buka'),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Buka 24 jam'),
                selected: _is24h,
                onSelected: (_) => setState(() => _is24h = true),
              ),
              ChoiceChip(
                label: const Text('Atur jam sendiri'),
                selected: !_is24h,
                onSelected: (_) => setState(() => _is24h = false),
              ),
            ],
          ),
          if (!_is24h) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(opening: true),
                    child: Text('Buka ${_hhmm(_open)}'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(opening: false),
                    child: Text('Tutup ${_hhmm(_close)}'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCashAndMap(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      children: [
        const _Label('Uang di laci sekarang'),
        MoneyField(controller: _balance),
        const SizedBox(height: 8),
        Text(
          'Hitung uang di laci saat ini. Angka ini jadi saldo awal kas. '
          'Kosongkan kalau laci masih kosong.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Tampilkan warung di peta pembeli',
                    style: theme.textTheme.titleSmall,
                  ),
                  value: _showOnMap,
                  onChanged: (value) => setState(() => _showOnMap = value),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    'Kalau dinyalakan, pembeli bisa melihat nama, lokasi, jam '
                    'buka, dan status barang (tersedia, terbatas, habis). '
                    'Jumlah stok, harga beli, dan kas tidak pernah ditampilkan. '
                    'Bisa diubah kapan saja di menu Akun.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}
