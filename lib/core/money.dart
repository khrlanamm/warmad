import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

// Rupiah amounts are whole integers everywhere in the app. Never use double
// for money: it cannot represent every amount exactly.

final NumberFormat _thousands = NumberFormat('#,###', 'id_ID');

/// Formats [amount] as "Rp15.500". Negative amounts use a real minus sign,
/// and [showPlus] adds "+" in front of positive amounts.
String formatRupiah(int amount, {bool showPlus = false}) {
  final digits = _thousands.format(amount.abs());
  final sign = amount < 0 ? '−' : (showPlus && amount > 0 ? '+' : '');
  return '${sign}Rp$digits';
}

/// Formats a plain quantity with thousand separators, for example "1.250".
String formatNumber(int value) => _thousands.format(value);

/// Reads the digits out of [text]. Returns null when there are none.
int? parseRupiah(String text) {
  final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  return int.parse(digits);
}

/// Keeps a money field formatted with thousand separators while typing.
class RupiahInputFormatter extends TextInputFormatter {
  const RupiahInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final value = parseRupiah(newValue.text);
    if (value == null) return TextEditingValue.empty;
    final text = _thousands.format(value);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
