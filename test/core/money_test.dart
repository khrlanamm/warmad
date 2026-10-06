import 'package:flutter_test/flutter_test.dart';
import 'package:warmad/core/money.dart';

void main() {
  group('formatRupiah', () {
    test('uses dots as thousand separators', () {
      expect(formatRupiah(0), 'Rp0');
      expect(formatRupiah(500), 'Rp500');
      expect(formatRupiah(15500), 'Rp15.500');
      expect(formatRupiah(1245000), 'Rp1.245.000');
    });

    test('puts a minus sign in front of negative amounts', () {
      expect(formatRupiah(-5000), '−Rp5.000');
    });

    test('adds a plus sign only when asked and only above zero', () {
      expect(formatRupiah(27500, showPlus: true), '+Rp27.500');
      expect(formatRupiah(0, showPlus: true), 'Rp0');
      expect(formatRupiah(-100, showPlus: true), '−Rp100');
    });

    test('keeps large amounts exact', () {
      expect(formatRupiah(9007199254740993), 'Rp9.007.199.254.740.993');
    });
  });

  group('parseRupiah', () {
    test('reads digits and ignores everything else', () {
      expect(parseRupiah('Rp15.500'), 15500);
      expect(parseRupiah('1 245 000'), 1245000);
      expect(parseRupiah('20000'), 20000);
    });

    test('returns null when there are no digits', () {
      expect(parseRupiah(''), isNull);
      expect(parseRupiah('Rp'), isNull);
    });

    test('round trips with formatRupiah', () {
      for (final amount in [0, 1, 999, 1000, 134400, 6412000]) {
        expect(parseRupiah(formatRupiah(amount)), amount);
      }
    });
  });

  group('RupiahInputFormatter', () {
    const formatter = RupiahInputFormatter();
    TextEditingValue type(String text) => formatter.formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(text: text),
    );

    test('adds separators while typing', () {
      expect(type('20000').text, '20.000');
      expect(type('20.0000').text, '200.000');
    });

    test('drops leading zeros and non digits', () {
      expect(type('007').text, '7');
      expect(type('12a3').text, '123');
    });

    test('clears the field when no digits remain', () {
      expect(type('').text, '');
      expect(type('.').text, '');
    });
  });
}
