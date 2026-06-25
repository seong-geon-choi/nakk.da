class TideStation {
  final String code;
  final String name;
  final double latitude;
  final double longitude;

  const TideStation({
    required this.code,
    required this.name,
    required this.latitude,
    required this.longitude,
  });
}

/// 당일 만조/간조 1회분 정보
class TideEvent {
  final String type; // '만조' or '간조'
  final String time; // 'HH:mm'
  final int? level; // 조위(cm), 없으면 null

  const TideEvent({required this.type, required this.time, this.level});
}
