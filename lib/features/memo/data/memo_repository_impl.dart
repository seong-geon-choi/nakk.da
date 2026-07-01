import 'dart:async';
import 'dart:io';
import '../domain/memo_repository.dart';
import '../domain/models/day_file.dart';
import '../domain/models/memo_entry.dart';
import '../domain/models/outing_info.dart';
import '../../location/domain/models/location_status.dart';
import '../../../core/services/saf_service.dart';
import '../../../core/services/tracking_service.dart';
import 'md_serializer.dart';

class MemoRepositoryImpl implements MemoRepository {
  final _saf = SafService();

  // 같은 파일에 대한 동시 쓰기 직렬화.
  // (헤더 생성 시 truncate 경합 + replaceBlock/removeBlock의 read-modify-write 경합 방지)
  final Map<String, Future<void>> _writeLocks = {};

  Future<T> _withLock<T>(String key, Future<T> Function() action) async {
    final prev = _writeLocks[key];
    final completer = Completer<void>();
    _writeLocks[key] = completer.future;
    try {
      if (prev != null) await prev;
      return await action();
    } finally {
      completer.complete();
      if (identical(_writeLocks[key], completer.future)) _writeLocks.remove(key);
    }
  }

  String _lockKey(DateTime date, String savePath) =>
      '$savePath/${_filenameFor(date)}';

  @override
  Future<DayFile?> loadDayFile(DateTime date, String savePath) async {
    if (savePath.isEmpty) return null;
    final filename = _filenameFor(date);
    String? content;
    if (SafService.isSafUri(savePath)) {
      content = await _saf.readFile(savePath, filename);
    } else {
      try {
        final file = File('$savePath/$filename');
        if (!await file.exists()) return null;
        content = await file.readAsString();
      } on FileSystemException catch (e) {
        if (e.osError?.errorCode == 13) return null;
        rethrow;
      }
    }
    if (content == null) return null;
    final blocks = MdSerializer.parseBlocks(content, date);
    final trackPoints = MdSerializer.parseTrackPoints(content);
    final outing = MdSerializer.parseOuting(content);
    return DayFile(
        date: date,
        filePath: '$savePath/$filename',
        blocks: blocks,
        trackPoints: trackPoints,
        outing: outing);
  }

  @override
  Future<void> saveOuting(DateTime date, OutingInfo outing, String savePath) =>
      _withLock(_lockKey(date, savePath), () async {
        final filename = _filenameFor(date);
        final dayFile = await loadDayFile(date, savePath);
        final blocks = dayFile?.blocks ?? const [];
        final points = dayFile?.trackPoints ?? const [];
        final content =
            MdSerializer.buildFullContent(date, blocks, points, outing);
        if (SafService.isSafUri(savePath)) {
          await _safEnsureHeader(savePath, filename, date);
          await _saf.writeFile(savePath, filename, content);
        } else {
          final file = File('$savePath/$filename');
          await _ensureHeader(file, date);
          await file.writeAsString(content);
        }
      });

  @override
  Future<void> appendEntry(DateTime date, MemoEntry entry, String savePath) =>
      _withLock(_lockKey(date, savePath), () async {
        final filename = _filenameFor(date);
        final toAppend = MdSerializer.serializeEntry(entry);
        if (SafService.isSafUri(savePath)) {
          await _safEnsureHeader(savePath, filename, date);
          await _saf.appendFile(savePath, filename, toAppend);
        } else {
          final file = File('$savePath/$filename');
          await _ensureHeader(file, date);
          await file.writeAsString(toAppend, mode: FileMode.append);
        }
      });

  @override
  Future<void> appendEntries(DateTime date, List<MemoEntry> entries, String savePath) {
    if (entries.isEmpty) return Future.value();
    return _withLock(_lockKey(date, savePath), () async {
      final filename = _filenameFor(date);
      final toAppend = entries.map(MdSerializer.serializeEntry).join();
      if (SafService.isSafUri(savePath)) {
        await _safEnsureHeader(savePath, filename, date);
        await _saf.appendFile(savePath, filename, toAppend);
      } else {
        final file = File('$savePath/$filename');
        await _ensureHeader(file, date);
        await file.writeAsString(toAppend, mode: FileMode.append);
      }
    });
  }

  @override
  Future<void> appendTrackPoints(DateTime date, List<TrackPoint> points, String savePath) {
    if (points.isEmpty) return Future.value();
    return _withLock(_lockKey(date, savePath), () async {
      final filename = _filenameFor(date);
      final toAppend = MdSerializer.trackCommentsFor(points);
      if (SafService.isSafUri(savePath)) {
        await _safEnsureHeader(savePath, filename, date);
        await _saf.appendFile(savePath, filename, toAppend);
      } else {
        final file = File('$savePath/$filename');
        await _ensureHeader(file, date);
        await file.writeAsString(toAppend, mode: FileMode.append);
      }
    });
  }

  @override
  Future<void> appendLocationBlock(DateTime date, LocationStatus loc, String savePath) =>
      _withLock(_lockKey(date, savePath), () async {
        final filename = _filenameFor(date);
        final toAppend = MdSerializer.serializeLocationBlock(loc);
        if (SafService.isSafUri(savePath)) {
          await _safEnsureHeader(savePath, filename, date);
          await _saf.appendFile(savePath, filename, toAppend);
        } else {
          final file = File('$savePath/$filename');
          await _ensureHeader(file, date);
          await file.writeAsString(toAppend, mode: FileMode.append);
        }
      });

  @override
  Future<void> replaceBlock(
          DateTime date, int blockIndex, dynamic newBlock, String savePath) =>
      _withLock(_lockKey(date, savePath), () async {
        final filename = _filenameFor(date);
        if (SafService.isSafUri(savePath)) {
          final dayFile = await loadDayFile(date, savePath);
          if (dayFile == null || blockIndex >= dayFile.blocks.length) return;
          final blocks = List<dynamic>.from(dayFile.blocks);
          blocks[blockIndex] = newBlock;
          await _saf.writeFile(
              savePath,
              filename,
              MdSerializer.buildFullContent(
                  date, blocks, dayFile.trackPoints, dayFile.outing));
        } else {
          final file = File('$savePath/$filename');
          if (!await file.exists()) return;
          final dayFile = await loadDayFile(date, savePath);
          if (dayFile == null || blockIndex >= dayFile.blocks.length) return;
          final blocks = List<dynamic>.from(dayFile.blocks);
          blocks[blockIndex] = newBlock;
          await file.writeAsString(MdSerializer.buildFullContent(
              date, blocks, dayFile.trackPoints, dayFile.outing));
        }
      });

  @override
  Future<void> removeBlock(DateTime date, int blockIndex, String savePath) =>
      _withLock(_lockKey(date, savePath), () async {
        final filename = _filenameFor(date);
        final dayFile = await loadDayFile(date, savePath);
        if (dayFile == null || blockIndex >= dayFile.blocks.length) return;
        final blocks = List<dynamic>.from(dayFile.blocks)..removeAt(blockIndex);
        final content = MdSerializer.buildFullContent(
            date, blocks, dayFile.trackPoints, dayFile.outing);
        if (SafService.isSafUri(savePath)) {
          await _saf.writeFile(savePath, filename, content);
        } else {
          await File('$savePath/$filename').writeAsString(content);
        }
      });

  String _filenameFor(DateTime date) {
    final y = date.year;
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d.md';
  }

  Future<void> _safEnsureHeader(String folderUri, String filename, DateTime date) async {
    if (!await _saf.fileExists(folderUri, filename)) {
      await _saf.writeFile(folderUri, filename, MdSerializer.fileHeader(date));
      await _saf.ensureFolder(folderUri);
    }
  }

  Future<void> _ensureHeader(File file, DateTime date) async {
    if (!await file.exists()) {
      await file.parent.create(recursive: true);
      await file.writeAsString(MdSerializer.fileHeader(date));
    }
    final noMedia = File('${file.parent.path}/.nomedia');
    if (!await noMedia.exists()) {
      try { await noMedia.create(); } catch (_) {}
    }
  }
}
