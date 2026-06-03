import 'dart:io';
import '../domain/file_list_repository.dart';
import '../domain/models/file_summary.dart';
import '../../../core/utils/file_name_parser.dart';

class FileListRepositoryImpl implements FileListRepository {
  @override
  Future<List<FileSummary>> listFiles(String savePath) async {
    final dir = Directory(savePath);
    if (!await dir.exists()) return [];

    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.md'))
        .cast<File>()
        .toList();

    final summaries = <FileSummary>[];
    for (final file in files) {
      final name = file.uri.pathSegments.last;
      final date = FileNameParser.parseDate(name);
      if (date == null) continue;

      final count = await _countEntries(file);
      summaries.add(FileSummary(
        date: date,
        filePath: file.path,
        displayName: name.replaceAll('.md', ''),
        entryCount: count,
      ));
    }

    summaries.sort((a, b) => b.date.compareTo(a.date));
    return summaries;
  }

  @override
  Future<void> renameFile(String filePath, String newDisplayName) async {
    final file = File(filePath);
    final dir = file.parent.path;
    final newPath = '$dir/$newDisplayName.md';
    await file.rename(newPath);
  }

  @override
  Future<void> copyFile(String filePath, String newDisplayName) async {
    final file = File(filePath);
    final dir = file.parent.path;
    final newPath = '$dir/$newDisplayName.md';
    await file.copy(newPath);
  }

  @override
  Future<void> deleteFile(String filePath, {bool deletePhotos = false}) async {
    if (deletePhotos) {
      await _deleteLinkedPhotos(filePath);
    }
    final file = File(filePath);
    if (await file.exists()) await file.delete();
  }

  Future<int> _countEntries(File file) async {
    int count = 0;
    final lines = await file.readAsLines();
    for (final line in lines) {
      if (line.startsWith('### ')) count++;
    }
    return count;
  }

  Future<void> _deleteLinkedPhotos(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return;
    final content = await file.readAsString();
    final pattern = RegExp(r'!\[\]\((photos/[^)]+)\)');
    final dir = File(filePath).parent.path;
    for (final match in pattern.allMatches(content)) {
      final photoPath = '$dir/${match.group(1)}';
      final photo = File(photoPath);
      if (await photo.exists()) await photo.delete();
    }
  }
}
