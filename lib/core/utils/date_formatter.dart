class DateFormatter {
  static String toDateString(DateTime date) {
    return '${date.year}-${_pad(date.month)}-${_pad(date.day)}';
  }

  static String toTimeString(DateTime time) {
    return '${_pad(time.hour)}:${_pad(time.minute)}';
  }

  static String toRelativeDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = today.difference(target).inDays;
    if (diff == 0) return '오늘';
    if (diff == 1) return '어제';
    if (diff < 7) return '$diff일 전';
    return toDateString(date);
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}
