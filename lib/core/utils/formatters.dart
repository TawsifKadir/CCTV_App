import 'package:intl/intl.dart';

/// Human-friendly date/number formatting helpers.
class Fmt {
  Fmt._();

  static final _date = DateFormat('d MMM yyyy');
  static final _dateTime = DateFormat('d MMM yyyy, h:mm a');
  static final _time = DateFormat('h:mm a');
  static final _weekday = DateFormat('EEE');

  static String date(DateTime? d) => d == null ? '—' : _date.format(d.toLocal());
  static String dateTime(DateTime? d) =>
      d == null ? '—' : _dateTime.format(d.toLocal());
  static String time(DateTime d) => _time.format(d.toLocal());
  static String weekday(DateTime d) => _weekday.format(d.toLocal());

  /// "Just now", "5 min ago", "Yesterday", or a date.
  static String relative(DateTime? d, {DateTime? now}) {
    if (d == null) return 'Never';
    final ref = now ?? DateTime.now();
    final diff = ref.difference(d);
    if (diff.isNegative || diff.inSeconds < 45) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24 && ref.day == d.day) {
      return '${diff.inHours} hr${diff.inHours == 1 ? '' : 's'} ago';
    }
    if (isSameDay(d, ref.subtract(const Duration(days: 1)))) {
      return 'Yesterday, ${time(d)}';
    }
    if (diff.inDays < 7) return '${diff.inDays < 2 ? 2 : diff.inDays} days ago';
    return date(d);
  }

  /// Employee number for display, e.g. "#1001".
  static String employeeNo(int? n) => n == null ? '—' : '#$n';

  /// Thousands-separated integer, e.g. 2,048.
  static String number(int n) => NumberFormat.decimalPattern().format(n);

  static String bytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  static String firstName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? name : parts.first;
  }

  static bool isSameDay(DateTime a, DateTime b) {
    final la = a.toLocal(), lb = b.toLocal();
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }

  static String greeting([DateTime? now]) {
    final h = (now ?? DateTime.now()).hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }
}
