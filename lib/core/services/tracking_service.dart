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
  static const _channel = MethodChannel('com.nakkda.nakkda/tracking');

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
