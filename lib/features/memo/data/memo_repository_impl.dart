import 'dart:io';
import '../domain/memo_repository.dart';
import '../domain/models/day_file.dart';
import '../domain/models/memo_entry.dart';
import '../../location/domain/models/location_status.dart';
import 'md_serializer.dart';

class MemoRepositoryImpl implements MemoRepository {
  @override
  Future<DayFile?> loadDayFile(DateTime date, String savePath) async {
    final file = _fileFor(date, savePath);
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    final blocks = MdSerializer.parseBlocks(content);
    return DayFile(date: date, filePath: file.path, blocks: blocks);
  }

  @override
  Future<void> appendEntry(
      DateTime date, MemoEntry entry, String savePath) async {
    final file = _fileFor(date, savePath);
    await _ensureHeader(file, date);
    await file.writeAsString(
      MdSerializer.serializeEntry(entry),
      mode: FileMode.append,
    );
  }

  @override
  Future<void> appendLocationBlock(
      DateTime date, LocationStatus loc, String savePath) async {
    final file = _fileFor(date, savePath);
    await _ensureHeader(file, date);
    await file.writeAsString(
      MdSerializer.serializeLocationBlock(loc),
      mode: FileMode.append,
    );
  }

  @override
  Future<void> replaceBlock(
      DateTime date, int blockIndex, dynamic newBlock, String savePath) async {
    final file = _fileFor(date, savePath);
    if (!await file.exists()) return;
    final dayFile = await loadDayFile(date, savePath);
    if (dayFile == null || blockIndex >= dayFile.blocks.length) return;
    final blocks = List<dynamic>.from(dayFile.blocks);
    blocks[blockIndex] = newBlock;
    await file.writeAsString(MdSerializer.buildFullContent(date, blocks));
  }

  @override
  Future<void> removeBlock(
      DateTime date, int blockIndex, String savePath) async {
    final file = _fileFor(date, savePath);
    if (!await file.exists()) return;
    final content = await file.readAsString();
    final newContent = MdSerializer.removeBlockAt(content, blockIndex);
    await file.writeAsString(newContent);
  }

  File _fileFor(DateTime date, String savePath) {
    final y = date.year;
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return File('$savePath/$y-$m-$d.md');
  }

  Future<void> _ensureHeader(File file, DateTime date) async {
    if (!await file.exists()) {
      await file.parent.create(recursive: true);
      await file.writeAsString(MdSerializer.fileHeader(date));
    }
  }
}
