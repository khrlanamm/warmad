import 'package:intl/intl.dart';

import 'dates.dart';

// Display-only date text in Indonesian. Needs `initializeDateFormatting`,
// which main() runs. Values that are stored or compared live in dates.dart.

/// "Selasa, 29 September 2026"
String formatLongDate(DateTime time) =>
    DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(time);

/// "29 Sep 2026, 23.41"
String formatDateTime(DateTime time) =>
    '${DateFormat('d MMM yyyy', 'id_ID').format(time)}, ${formatClock(time)}';

/// How long ago [time] was, in everyday words: "Baru saja", "10 menit lalu",
/// "3 jam lalu", then the date and time.
String formatRelative(DateTime time, DateTime now) {
  final elapsed = now.difference(time);
  if (elapsed.inMinutes < 1) return 'Baru saja';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} menit lalu';
  if (elapsed.inHours < 12) return '${elapsed.inHours} jam lalu';
  return formatDateTime(time);
}

/// Which heading a notification from [time] goes under.
String dayGroupOf(DateTime time, DateTime now) {
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(time.year, time.month, time.day)).inDays;
  return switch (days) {
    <= 0 => 'Hari ini',
    1 => 'Kemarin',
    _ => 'Sebelumnya',
  };
}

/// [formatRelative] for the middle of a sentence: "diperbarui baru saja",
/// "diperbarui 5 Okt 2026, 18.10". Only the first letter is lowered, so
/// month names keep their capital.
String formatRelativeInline(DateTime time, DateTime now) {
  final text = formatRelative(time, now);
  return text[0].toLowerCase() + text.substring(1);
}
