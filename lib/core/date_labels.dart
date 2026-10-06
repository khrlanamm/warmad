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
