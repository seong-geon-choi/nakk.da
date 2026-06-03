class FileSummary {
  final DateTime date;
  final String filePath;
  final String displayName; // 파일명(확장자 제외), 날짜 외 이름도 허용
  final int entryCount;    // ### HH:mm 헤더 수

  const FileSummary({
    required this.date,
    required this.filePath,
    required this.displayName,
    required this.entryCount,
  });
}
