import 'dart:io';
import '../domain/file_list_repository.dart';
import '../domain/models/file_summary.dart';
import '../../../core/services/saf_service.dart';
import '../../../core/utils/file_name_parser.dart';

class FileListRepositoryImpl implements FileListRepository {
  final _saf = SafService();

  @override
  Future<List<FileSummary>> listFiles(String savePath) async {
    if (savePath.isEmpty) return [];
    if (SafService.isSafUri(savePath)) {
      return _listFilesSaf(savePath);
    }
    return _listFilesLocal(savePath);
  }

  Future<List<FileSummary>> _listFilesSaf(String folderUri) async {
    final names = await _saf.listMdFiles(folderUri);
    final displayPath = await _saf.getDisplayPath(folderUri);
    final summaries = <FileSummary>[];
    for (final name in names) {
      final date = FileNameParser.parseDate(name);
      if (date == null) continue;
      final content = await _saf.readFile(folderUri, name) ?? '';
      summaries.add(FileSummary(
        date: date,
        filePath: '$folderUri/$name',
        displayName: name.replaceAll('.md', ''),
        entryCount: _countEntries(content),
        displayFolderPath: displayPath,
        address: _extractAddress(content),
      ));
    }
    summaries.sort((a, b) => b.date.compareTo(a.date));
    return summaries;
  }

  Future<List<FileSummary>> _listFilesLocal(String savePath) async {
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
      final content = await file.readAsString();
      summaries.add(FileSummary(
        date: date,
        filePath: file.path,
        displayName: name.replaceAll('.md', ''),
        entryCount: _countEntries(content),
        displayFolderPath: savePath,
        address: _extractAddress(content),
      ));
    }
    summaries.sort((a, b) => b.date.compareTo(a.date));
    return summaries;
  }

  @override
  Future<void> renameFile(String filePath, String newDisplayName, String savePath) async {
    final filename = filePath.split('/').last;
    if (SafService.isSafUri(savePath)) {
      await _saf.renameFile(savePath, filename, '$newDisplayName.md');
    } else {
      final file = File(filePath);
      final dir = file.parent.path;
      await file.rename('$dir/$newDisplayName.md');
    }
  }

  @override
  Future<void> copyFile(String filePath, String newDisplayName, String savePath) async {
    final filename = filePath.split('/').last;
    if (SafService.isSafUri(savePath)) {
      await _saf.copyFile(savePath, filename, '$newDisplayName.md');
    } else {
      final file = File(filePath);
      final dir = file.parent.path;
      await file.copy('$dir/$newDisplayName.md');
    }
  }

  @override
  Future<void> deleteFile(String filePath, String savePath, {bool deletePhotos = false}) async {
    final filename = filePath.split('/').last;
    if (SafService.isSafUri(savePath)) {
      if (deletePhotos) await _deleteLinkedPhotosSaf(savePath, filename);
      await _saf.deleteFile(savePath, filename);
    } else {
      if (deletePhotos) await _deleteLinkedPhotosLocal(filePath);
      final file = File(filePath);
      if (await file.exists()) await file.delete();
    }
  }

  @override
  Future<int> cleanUnusedPhotos(String savePath) async {
    if (savePath.isEmpty) return 0;

    // 모든 .md 파일에서 참조된 photos/ 파일명 수집
    final referenced = <String>{};
    if (SafService.isSafUri(savePath)) {
      final names = await _saf.listMdFiles(savePath);
      for (final name in names) {
        final content = await _saf.readFile(savePath, name) ?? '';
        _extractPhotoFilenames(content, referenced);
      }
    } else {
      final dir = Directory(savePath);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File && entity.path.endsWith('.md')) {
            _extractPhotoFilenames(await entity.readAsString(), referenced);
          }
        }
      }
    }

    // photos/ 폴더의 파일 중 미참조 파일 삭제
    int deleted = 0;
    if (SafService.isSafUri(savePath)) {
      final photos = await _saf.listPhotosFolder(savePath);
      for (final filename in photos) {
        if (!referenced.contains(filename)) {
          await _saf.deletePhotoFile(savePath, filename);
          deleted++;
        }
      }
    } else {
      final photosDir = Directory('$savePath/photos');
      if (await photosDir.exists()) {
        await for (final entity in photosDir.list()) {
          if (entity is File) {
            final filename = entity.uri.pathSegments.last;
            if (!referenced.contains(filename)) {
              await entity.delete();
              deleted++;
            }
          }
        }
      }
    }
    return deleted;
  }

  void _extractPhotoFilenames(String content, Set<String> out) {
    for (final m in RegExp(r'!\[\]\(photos/([^)]+)\)').allMatches(content)) {
      out.add(m.group(1)!);
    }
  }

  int _countEntries(String content) {
    // 줄 시작이 정확히 '### '인 경우만 카운트 ('#### ' 등 하위 헤더 제외)
    return RegExp(r'^### ', multiLine: true).allMatches(content).length;
  }

  String? _extractAddress(String content) {
    final match = RegExp(r'- 📍 (.+)').firstMatch(content);
    return match?.group(1)?.trim();
  }

  Future<void> _deleteLinkedPhotosSaf(String folderUri, String filename) async {
    final content = await _saf.readFile(folderUri, filename) ?? '';
    final pattern = RegExp(r'!\[\]\(([^)]+)\)');
    for (final match in pattern.allMatches(content)) {
      final photoPath = match.group(1);
      if (photoPath != null && !photoPath.startsWith('/')) continue; // 상대경로는 무시
      if (photoPath != null) {
        try { await File(photoPath).delete(); } catch (_) {}
      }
    }
  }

  Future<void> _deleteLinkedPhotosLocal(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return;
    final content = await file.readAsString();
    final pattern = RegExp(r'!\[\]\((photos/[^)]+)\)');
    final dir = File(filePath).parent.path;
    for (final match in pattern.allMatches(content)) {
      final photo = File('$dir/${match.group(1)}');
      if (await photo.exists()) await photo.delete();
    }
  }
}
