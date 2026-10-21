class MemoEntry {
  final DateTime timestamp;
  final double? latitude;
  final double? longitude;
  final String? text;
  final String? photoPath;
  final String? videoPath;
  final double? fishLength;
  final String? fishSpecies;
  // 알림 조과 기록으로 적재된 항목(시각·위치·어종만). 메모 목록에는 숨기고
  // 지도·집계에만 사용한다. MD에는 '- 🎣' 라인으로 구분 저장된다.
  final bool quickCatch;

  const MemoEntry({
    required this.timestamp,
    this.latitude,
    this.longitude,
    this.text,
    this.photoPath,
    this.videoPath,
    this.fishLength,
    this.fishSpecies,
    this.quickCatch = false,
  });

  bool get isPhoto => photoPath != null;
  bool get isVideo => videoPath != null;
  bool get hasGps => latitude != null && longitude != null;

  String get timeLabel {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
