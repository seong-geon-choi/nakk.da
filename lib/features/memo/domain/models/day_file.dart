import '../../../location/domain/models/location_status.dart';
import 'memo_entry.dart';

class DayFile {
  final DateTime date;
  final String filePath;
  final List<dynamic> blocks; // MemoEntry | LocationStatus 순서 유지

  const DayFile({
    required this.date,
    required this.filePath,
    required this.blocks,
  });

  List<MemoEntry> get entries =>
      blocks.whereType<MemoEntry>().toList();

  List<LocationStatus> get locationBlocks =>
      blocks.whereType<LocationStatus>().toList();
}
