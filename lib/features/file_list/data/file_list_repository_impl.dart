import 'dart:io';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
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
    // 독립적인 I/O(목록·표시경로·수정시간·캐시)를 동시에 수행해 지연을 줄인다.
    // getFilesModifiedTimes는 이제 폴더 전체 자식을 반환하므로 names가 필요 없다.
    final (names, displayPath, mtimes, cache) = await (
      _saf.listMdFiles(folderUri),
      _saf.getDisplayPath(folderUri),
      _saf.getFilesModifiedTimes(folderUri, const []),
      _loadCache(folderUri),
    ).wait;
    final newCache = <String, _CachedSummary>{};

    // 1) 수정시간이 같은(캐시 적중) 파일은 재사용, 나머지만 읽을 목록에 모은다
    final toRead = <String>[];
    for (final name in names) {
      if (FileNameParser.parseDate(name) == null) continue;
      final mtime = mtimes[name]?.millisecondsSinceEpoch ?? 0;
      final cached = cache[name];
      if (cached != null && mtime != 0 && cached.mtime == mtime) {
        newCache[name] = cached;
      } else {
        toRead.add(name);
      }
    }

    // 2) 변경/신규 파일만 병렬로 읽어 요약 계산 (SAF 왕복을 동시 처리)
    final read = await Future.wait(toRead.map((name) async {
      final content = await _saf.readFile(folderUri, name) ?? '';
      return MapEntry(
        name,
        _CachedSummary(
          mtime: mtimes[name]?.millisecondsSinceEpoch ?? 0,
          entryCount: _countEntries(content),
          address: _extractAddress(content),
        ),
      );
    }));
    for (final e in read) {
      newCache[e.key] = e.value;
    }

    // 3) FileSummary 조립
    final summaries = <FileSummary>[];
    for (final name in names) {
      final date = FileNameParser.parseDate(name);
      final c = newCache[name];
      if (date == null || c == null) continue;
      summaries.add(FileSummary(
        date: date,
        filePath: '$folderUri/$name',
        displayName: name.replaceAll('.md', ''),
        entryCount: c.entryCount,
        displayFolderPath: displayPath,
        address: c.address,
      ));
    }
    summaries.sort((a, b) => b.date.compareTo(a.date));
    await _saveCache(folderUri, newCache);
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
    final cache = await _loadCache(savePath);
    final newCache = <String, _CachedSummary>{};
    final summaries = <FileSummary>[];

    // 파일별 요약을 병렬로 계산(수정시간이 같으면 캐시 재사용해 읽기 생략)
    await Future.wait(files.map((file) async {
      final name = file.uri.pathSegments.last;
      final date = FileNameParser.parseDate(name);
      if (date == null) return;
      final mtime = (await file.stat()).modified.millisecondsSinceEpoch;
      final cached = cache[name];
      final _CachedSummary summary;
      if (cached != null && cached.mtime == mtime) {
        summary = cached;
      } else {
        final content = await file.readAsString();
        summary = _CachedSummary(
          mtime: mtime,
          entryCount: _countEntries(content),
          address: _extractAddress(content),
        );
      }
      newCache[name] = summary;
      summaries.add(FileSummary(
        date: date,
        filePath: file.path,
        displayName: name.replaceAll('.md', ''),
        entryCount: summary.entryCount,
        displayFolderPath: savePath,
        address: summary.address,
      ));
    }));
    summaries.sort((a, b) => b.date.compareTo(a.date));
    await _saveCache(savePath, newCache);
    return summaries;
  }

  // ── 요약 캐시 (수정시간 기반) ───────────────────────────────
  static const _cachePrefix = 'file_summary_cache_v1:';

  Future<Map<String, _CachedSummary>> _loadCache(String savePath) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_cachePrefix$savePath');
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) {
        final m = v as Map<String, dynamic>;
        return MapEntry(
          k,
          _CachedSummary(
            mtime: m['m'] as int,
            entryCount: m['c'] as int,
            address: m['a'] as String?,
          ),
        );
      });
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveCache(
      String savePath, Map<String, _CachedSummary> cache) async {
    final prefs = await SharedPreferences.getInstance();
    final map = cache.map((k, v) =>
        MapEntry(k, {'m': v.mtime, 'c': v.entryCount, 'a': v.address}));
    await prefs.setString('$_cachePrefix$savePath', jsonEncode(map));
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

/// 파일 목록 요약 캐시 항목 (수정시간이 같으면 파일을 다시 읽지 않는다)
class _CachedSummary {
  final int mtime; // millisecondsSinceEpoch
  final int entryCount;
  final String? address;
  const _CachedSummary({
    required this.mtime,
    required this.entryCount,
    required this.address,
  });
}
