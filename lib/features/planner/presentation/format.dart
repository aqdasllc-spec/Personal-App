const _weekdaysLong = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _weekdaysShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthsLong = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const _monthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String weekdayLong(int weekday) => _weekdaysLong[weekday - 1];
String weekdayShort(int weekday) => _weekdaysShort[weekday - 1];
String monthLong(int month) => _monthsLong[month - 1];
String monthShort(int month) => _monthsShort[month - 1];

String two(int v) => v.toString().padLeft(2, '0');
String timeLabel(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

/// "Friday 6 November"
String dayTitle(DateTime d) => '${weekdayLong(d.weekday)} ${d.day} ${monthLong(d.month)}';

/// "6 Nov 2026"
String dateLabel(DateTime d) => '${d.day} ${monthShort(d.month)} ${d.year}';

/// "2 – 8 Nov 2026" (months/years shown only where they change)
String weekTitle(DateTime monday) {
  final end = DateTime(monday.year, monday.month, monday.day + 6);
  if (monday.month == end.month) return '${monday.day} – ${end.day} ${monthShort(end.month)} ${end.year}';
  if (monday.year == end.year) return '${monday.day} ${monthShort(monday.month)} – ${end.day} ${monthShort(end.month)} ${end.year}';
  return '${dateLabel(monday)} – ${dateLabel(end)}';
}

String monthTitle(DateTime d) => '${monthLong(d.month)} ${d.year}';

String durationLabel(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

String reminderLabel(int? minutes) => switch (minutes) {
      null => 'No reminder',
      0 => 'At the time',
      5 => '5 minutes before',
      15 => '15 minutes before',
      30 => '30 minutes before',
      60 => '1 hour before',
      120 => '2 hours before',
      1440 => '1 day before',
      2880 => '2 days before',
      _ => minutes >= 1440 && minutes % 1440 == 0 ? '${minutes ~/ 1440} days before' : minutes >= 60 && minutes % 60 == 0 ? '${minutes ~/ 60} hours before' : '$minutes minutes before',
    };

const reminderChoices = <int?>[null, 0, 5, 15, 30, 60, 1440];
