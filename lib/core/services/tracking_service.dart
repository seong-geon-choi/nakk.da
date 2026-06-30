import 'package:flutter/services.dart';

class TrackPoint {
  final double lat, lng;
  final DateTime timestamp;

  const TrackPoint({
    required this.lat,
    required this.lng,
    required this.timestamp,
  });

  static TrackPoint? fromString(String s) {
    final parts = s.split(',');
    if (parts.length != 3) return null;
    final lat = double.tryParse(parts[0]);
    final lng = double.tryParse(parts[1]);
    final dt = DateTime.tryParse(parts[2]);
    if (lat == null || lng == null || dt == null) return null;
    return TrackPoint(lat: lat, lng: lng, timestamp: dt);
  }
}

class TrackingService {
  static const _channel = MethodChannel('com.sgchoisg.nakkda/tracking');

  Future<void> startTracking(int intervalMeters) =>
      _channel.invokeMethod('startTracking', {'intervalMeters': intervalMeters});

  Future<void> stopTracking() => _channel.invokeMethod('stopTracking');

  Future<bool> isTracking() async {
    try {
      return await _channel.invokeMethod<bool>('isTracking') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setQuickLaunchMode(String mode, double shakeThresholdG) async {
    try {
      await _channel.invokeMethod('setQuickLaunchMode', {
        'mode': mode,
        'shakeThresholdG': shakeThresholdG,
      });
    } catch (_) {}
  }

  /// 출퇴근 알림 설정을 네이티브에 동기화(활성 시 스케줄/서비스 갱신).
  Future<void> commuteSync(Map<String, dynamic> config) async {
    try {
      await _channel.invokeMethod('commuteSync', config);
    } catch (_) {}
  }

  /// 출퇴근 알림 중지(스케줄·서비스 해제).
  Future<void> commuteStop() async {
    try {
      await _channel.invokeMethod('commuteStop');
    } catch (_) {}
  }

  /// 네이티브 출퇴근 감시 활성 여부. 알림 스와이프로 중단되면 false.
  Future<bool> commuteIsActive() async {
    try {
      return await _channel.invokeMethod<bool>('commuteIsActive') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<List<TrackPoint>> getAndClearTrackPoints() async {
    try {
      final list =
          await _channel.invokeListMethod<String>('getAndClearTrackPoints') ??
              [];
      return list
          .map(TrackPoint.fromString)
          .whereType<TrackPoint>()
          .toList();
    } catch (_) {
      return [];
    }
  }
}
