import 'models/day_file.dart';
import 'models/memo_entry.dart';
import '../../location/domain/models/location_status.dart';

abstract interface class MemoRepository {
  Future<DayFile?> loadDayFile(DateTime date, String savePath);
  Future<void> appendEntry(DateTime date, MemoEntry entry, String savePath);
  Future<void> appendLocationBlock(DateTime date, LocationStatus loc, String savePath);
  Future<void> removeBlock(DateTime date, int blockIndex, String savePath);
  Future<void> replaceBlock(DateTime date, int blockIndex, dynamic newBlock, String savePath);
}
