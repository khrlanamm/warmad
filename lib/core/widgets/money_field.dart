import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../money.dart';

/// Large Rupiah input with a fixed "Rp" in front and thousand separators.
/// Read the amount with [parseRupiah] on the controller text.
class MoneyField extends StatelessWidget {
  const MoneyField({
    super.key,
    required this.controller,
    this.fontSize = 28,
    this.autofocus = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final double fontSize;
  final bool autofocus;

  /// Called with the typed amount, or null when the field is empty.
  final ValueChanged<int?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final muted = AppText.money(fontSize, color: AppColors.inkMuted);
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: TextInputType.number,
      inputFormatters: const [RupiahInputFormatter()],
      style: AppText.money(fontSize),
      onChanged: onChanged == null
          ? null
          : (text) => onChanged!(parseRupiah(text)),
      decoration: InputDecoration(
        hintText: '0',
        hintStyle: muted,
        // A prefix icon stays visible when the field is empty and unfocused;
        // prefixText does not.
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 16, right: 6),
          child: Text('Rp', style: muted),
        ),
        prefixIconConstraints: const BoxConstraints(),
      ),
    );
  }
}
