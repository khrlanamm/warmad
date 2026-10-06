import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warmad/core/firebase/function_errors.dart';

FirebaseFunctionsException error(String code, String? message) =>
    FirebaseFunctionsException(code: code, message: message ?? code);

void main() {
  test('shows the message our own functions wrote', () {
    expect(
      functionErrorMessage(
        error('failed-precondition', 'Kode undangan ini sudah dipakai.'),
      ),
      'Kode undangan ini sudah dipakai.',
    );
  });

  test('hides bare platform status names', () {
    expect(
      functionErrorMessage(error('unauthenticated', 'UNAUTHENTICATED')),
      'Gagal. Cek internet, lalu coba lagi.',
    );
    expect(
      functionErrorMessage(error('internal', 'internal'), fallback: 'Gagal.'),
      'Gagal.',
    );
  });

  test('asks for a connection when the server cannot be reached', () {
    expect(
      functionErrorMessage(error('unavailable', 'UNAVAILABLE')),
      'Butuh internet. Coba lagi.',
    );
  });

  test('keeps the message of an expired invite code', () {
    expect(
      functionErrorMessage(
        error('deadline-exceeded', 'Kode undangan sudah kedaluwarsa.'),
      ),
      'Kode undangan sudah kedaluwarsa.',
    );
  });

  test('falls back for errors that are not from a function', () {
    expect(functionErrorMessage(StateError('x'), fallback: 'Gagal.'), 'Gagal.');
  });
}
