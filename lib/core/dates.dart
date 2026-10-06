// Built by hand instead of with DateFormat: these values are stored and
// compared, so they must not change with the device locale or its digits.

String _two(int value) => value.toString().padLeft(2, '0');

/// The calendar day of [time] on this device, as "2026-10-06". Daily reports
/// are grouped by this key.
String dayKeyOf(DateTime time) =>
    '${time.year.toString().padLeft(4, '0')}-${_two(time.month)}-${_two(time.day)}';

/// Clock time the Indonesian way, for example "14.32".
String formatClock(DateTime time) => '${_two(time.hour)}.${_two(time.minute)}';
