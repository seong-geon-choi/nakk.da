class LocationStatus {
  final DateTime timestamp;
  final double? latitude;
  final double? longitude;
  final String? address;
  // Phase 2 필드 (현재는 항상 null)
  final double? temperature;
  final String? tideName;
  final String? tideTime;
  final double? waterTemp;
  final String? stationName;
  final double? stationDistance;
  final bool isMove; // 이동으로 추가된 현황 블록 여부
  final double? windSpeed;
  final int? windDeg;
  final int? weatherCode;

  const LocationStatus({
    required this.timestamp,
    this.latitude,
    this.longitude,
    this.address,
    this.temperature,
    this.tideName,
    this.tideTime,
    this.waterTemp,
    this.stationName,
    this.stationDistance,
    this.isMove = false,
    this.windSpeed,
    this.windDeg,
    this.weatherCode,
  });
}
