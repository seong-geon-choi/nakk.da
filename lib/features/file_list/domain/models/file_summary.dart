class FileSummary {
  final DateTime date;
  final String filePath;
  final String displayName;
  final int entryCount;
  final String displayFolderPath; // UI 표시용 폴더 경로
  final String? address;

  const FileSummary({
    required this.date,
    required this.filePath,
    required this.displayName,
    required this.entryCount,
    this.displayFolderPath = '',
    this.address,
  });
}
