class MemoEntry {
  final DateTime timestamp;
  final double? latitude;
  final double? longitude;
  final String? text;
  final String? photoPath;
  final String? videoPath;
  final double? fishLength;
  final String? fishSpecies;

  const MemoEntry({
    required this.timestamp,
    this.latitude,
    this.longitude,
    this.text,
    this.photoPath,
    this.videoPath,
    this.fishLength,
    this.fishSpecies,
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
