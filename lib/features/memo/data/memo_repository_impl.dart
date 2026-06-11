import 'dart:io';
import '../domain/memo_repository.dart';
import '../domain/models/day_file.dart';
import '../domain/models/memo_entry.dart';
import '../../location/domain/models/location_status.dart';
import '../../../core/services/saf_service.dart';
import '../../../core/services/tracking_service.dart';
import 'md_serializer.dart';

class MemoRepositoryImpl implements MemoRepository {
  final _saf = SafService();

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
    return DayFile(date: date, filePath: '$savePath/$filename', blocks: blocks, trackPoints: trackPoints);
  }

  @override
  Future<void> appendEntry(DateTime date, MemoEntry entry, String savePath) async {
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
  }

  @override
  Future<void> appendEntries(DateTime date, List<MemoEntry> entries, String savePath) async {
    if (entries.isEmpty) return;
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
  }

  @override
  Future<void> appendTrackPoints(DateTime date, List<TrackPoint> points, String savePath) async {
    if (points.isEmpty) return;
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
  }

  @override
  Future<void> appendLocationBlock(DateTime date, LocationStatus loc, String savePath) async {
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
  }

  @override
  Future<void> replaceBlock(
      DateTime date, int blockIndex, dynamic newBlock, String savePath) async {
    final filename = _filenameFor(date);
    if (SafService.isSafUri(savePath)) {
      final dayFile = await loadDayFile(date, savePath);
      if (dayFile == null || blockIndex >= dayFile.blocks.length) return;
      final blocks = List<dynamic>.from(dayFile.blocks);
      blocks[blockIndex] = newBlock;
      await _saf.writeFile(savePath, filename,
          MdSerializer.buildFullContent(date, blocks, dayFile.trackPoints));
    } else {
      final file = File('$savePath/$filename');
      if (!await file.exists()) return;
      final dayFile = await loadDayFile(date, savePath);
      if (dayFile == null || blockIndex >= dayFile.blocks.length) return;
      final blocks = List<dynamic>.from(dayFile.blocks);
      blocks[blockIndex] = newBlock;
      await file.writeAsString(
          MdSerializer.buildFullContent(date, blocks, dayFile.trackPoints));
    }
  }

  @override
  Future<void> removeBlock(DateTime date, int blockIndex, String savePath) async {
    final filename = _filenameFor(date);
    final dayFile = await loadDayFile(date, savePath);
    if (dayFile == null || blockIndex >= dayFile.blocks.length) return;
    final blocks = List<dynamic>.from(dayFile.blocks)..removeAt(blockIndex);
    final content = MdSerializer.buildFullContent(date, blocks, dayFile.trackPoints);
    if (SafService.isSafUri(savePath)) {
      await _saf.writeFile(savePath, filename, content);
    } else {
      await File('$savePath/$filename').writeAsString(content);
    }
  }

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
