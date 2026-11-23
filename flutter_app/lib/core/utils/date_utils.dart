import 'package:intl/intl.dart';

class AppDateUtils {
  AppDateUtils._();

  static final _displayFormat = DateFormat('dd MMM yyyy');
  static final _shortFormat = DateFormat('dd/MM/yyyy');
  static final _timeFormat = DateFormat('hh:mm a');
  static final _fullFormat = DateFormat('dd MMM yyyy, hh:mm a');

  static String display(DateTime dt) => _displayFormat.format(dt);
  static String short(DateTime dt) => _shortFormat.format(dt);
  static String time(DateTime dt) => _timeFormat.format(dt);
  static String full(DateTime dt) => _fullFormat.format(dt);
  static DateTime expiryDate(DateTime manufactureDate, int monthsToAdd) {
    if (monthsToAdd == 0) return manufactureDate;

    // Calculate the new year and month
    int newYear = manufactureDate.year + (manufactureDate.month + monthsToAdd - 1) ~/ 12;
    int newMonth = (manufactureDate.month + monthsToAdd - 1) % 12 + 1;
    int newDay = manufactureDate.day;

    // Handle end-of-month overflow (e.g. if original was Jan 31, but new month only has 28 days)
    // DateTime(year, month + 1, 0) gives the last day of the target month.
    int lastDayOfNewMonth = DateTime(newYear, newMonth + 1, 0).day;
    if (newDay > lastDayOfNewMonth) {
      newDay = lastDayOfNewMonth;
    }
    return DateTime(
      newYear,
      newMonth,
      newDay-1,
      manufactureDate.hour,
      manufactureDate.minute,
      manufactureDate.second,
    );
  }

  static String dateCodingLabel(DateTime manufacture, DateTime expiry) {
    return '${short(manufacture)} – ${short(expiry)}';
  }

  static String timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  static DateTime startOfWeek(DateTime dt) {
    return dt.subtract(Duration(days: dt.weekday - 1));
  }

  static DateTime startOfMonth(DateTime dt) {
    return DateTime(dt.year, dt.month, 1);
  }

  static DateTime endOfDay(DateTime dt) {
    return DateTime(dt.year, dt.month, dt.day, 23, 59, 59);
  }
}
