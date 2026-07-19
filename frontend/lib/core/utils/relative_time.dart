/// Formats a timestamp as a short relative string, e.g. "2 days ago".
///
/// Falls back to an absolute date for anything older than ~4 weeks.
String relativeTime(DateTime time, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final diff = reference.difference(time);

  if (diff.isNegative) return 'just now';
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return '$m ${m == 1 ? 'minute' : 'minutes'} ago';
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return '$h ${h == 1 ? 'hour' : 'hours'} ago';
  }
  if (diff.inDays < 7) {
    final d = diff.inDays;
    return '$d ${d == 1 ? 'day' : 'days'} ago';
  }
  if (diff.inDays < 28) {
    final w = (diff.inDays / 7).floor();
    return '$w ${w == 1 ? 'week' : 'weeks'} ago';
  }
  return absoluteDate(time);
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// e.g. "5 Jan 2026".
String absoluteDate(DateTime time) {
  final t = time.toLocal();
  return '${t.day} ${_months[t.month - 1]} ${t.year}';
}

/// e.g. "5 Jan 2026, 3:04 PM".
String absoluteDateTime(DateTime time) {
  final t = time.toLocal();
  final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final minute = t.minute.toString().padLeft(2, '0');
  final ampm = t.hour < 12 ? 'AM' : 'PM';
  return '${absoluteDate(time)}, $hour12:$minute $ampm';
}
