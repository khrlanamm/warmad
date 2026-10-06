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
