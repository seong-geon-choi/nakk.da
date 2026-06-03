class FileNameParser {
  static final _pattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})\.md$');

  static DateTime? parseDate(String fileName) {
    final match = _pattern.firstMatch(fileName);
    if (match == null) return null;
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  static bool isDateFile(String fileName) => _pattern.hasMatch(fileName);

  static String toFileName(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}.md';
}
