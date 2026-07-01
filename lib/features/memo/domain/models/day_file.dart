import '../../../location/domain/models/location_status.dart';
import '../../../../core/services/tracking_service.dart';
import 'memo_entry.dart';
import 'outing_info.dart';

class DayFile {
  final DateTime date;
  final String filePath;
  final List<dynamic> blocks; // MemoEntry | LocationStatus 순서 유지
  final List<TrackPoint> trackPoints;
  final OutingInfo? outing; // 하루 단위 출조 정보(태클·조과)

  const DayFile({
    required this.date,
    required this.filePath,
    required this.blocks,
    this.trackPoints = const [],
    this.outing,
  });

  List<MemoEntry> get entries =>
      blocks.whereType<MemoEntry>().toList();

  List<LocationStatus> get locationBlocks =>
      blocks.whereType<LocationStatus>().toList();
}
