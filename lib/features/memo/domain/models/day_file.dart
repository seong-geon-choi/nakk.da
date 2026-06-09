import '../../../location/domain/models/location_status.dart';
import '../../../../core/services/tracking_service.dart';
import 'memo_entry.dart';

class DayFile {
  final DateTime date;
  final String filePath;
  final List<dynamic> blocks; // MemoEntry | LocationStatus 순서 유지
  final List<TrackPoint> trackPoints;

  const DayFile({
    required this.date,
    required this.filePath,
    required this.blocks,
    this.trackPoints = const [],
  });

  List<MemoEntry> get entries =>
      blocks.whereType<MemoEntry>().toList();

  List<LocationStatus> get locationBlocks =>
      blocks.whereType<LocationStatus>().toList();
}
