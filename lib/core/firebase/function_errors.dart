import 'package:cloud_functions/cloud_functions.dart';

/// Turns a failed Cloud Function call into a sentence for the user.
///
/// Our functions throw messages written in Indonesian, which are shown as
/// they are. Errors raised by the platform itself carry a bare status name
/// such as "UNAUTHENTICATED"; those are replaced with [fallback].
String functionErrorMessage(
  Object error, {
  String fallback = 'Gagal. Cek internet, lalu coba lagi.',
}) {
  if (error is! FirebaseFunctionsException) return fallback;
  if (error.code == 'unavailable' || error.code == 'deadline-exceeded') {
    // deadline-exceeded is also what an expired invite code returns, with
    // its own message.
    final message = error.message;
    if (message != null && !isBareStatus(message)) return message;
    return 'Butuh internet. Coba lagi.';
  }
  final message = error.message;
  if (message == null || isBareStatus(message)) return fallback;
  return message;
}

/// True for platform status names like "INTERNAL" or "UNAUTHENTICATED".
bool isBareStatus(String message) =>
    RegExp(r'^[A-Za-z_]+$').hasMatch(message.trim());
