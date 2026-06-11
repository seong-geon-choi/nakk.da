import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../memo/domain/models/memo_entry.dart';
import '../../memo/presentation/memo_provider.dart';
import '../../location/domain/models/location_status.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/file_name_parser.dart';
import '../../../core/services/saf_service.dart';
import '../../../core/services/tracking_service.dart';
import '../../../core/widgets/memo_date_picker_dialog.dart';
import '../../../core/widgets/saf_image.dart';
import '../../../core/widgets/video_player_widget.dart';

class MapScreen extends ConsumerStatefulWidget {
  final String? filePath;
  const MapScreen({super.key, this.filePath});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  List<_GpsPoint> _points = [];
  List<TrackPoint> _trackPoints = [];
  _GpsPoint? _selected;
  bool _showLines = false;
  bool _showTimes = false;
  bool _showDistances = false;
  bool _showTrack = false;
  bool _showToast = false;
  String _toastMsg = '';
  Timer? _toastTimer;
  Timer? _noGpsTimer;
  bool _dismissedNoGpsCard = false;
  DateTime _loadedDate = DateTime.now();
  MapController _mapController = MapController();
  double _zoom = 14;
  String _savePath = '';

  @override
  void dispose() {
    _toastTimer?.cancel();
    _noGpsTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadFromToday();
    _loadTrackPoints();
    ref.read(settingsProvider.future).then((s) {
      if (mounted) setState(() => _savePath = s.savePath);
    });
  }

  void _loadFromToday() {
    final fp = widget.filePath;
    if (fp != null) {
      final file = ref.read(dayFileProvider(fp)).valueOrNull;
      final date = FileNameParser.parseDate(fp.split('/').last.split('\\').last) ?? DateTime.now();
      _applyBlocks(file?.blocks ?? [], date);
    } else {
      final file = ref.read(todayFileProvider).valueOrNull;
      _applyBlocks(file?.blocks ?? [], DateTime.now());
    }
  }

  void _applyBlocks(List<dynamic> blocks, DateTime date) {
    final pts = <_GpsPoint>[];
    for (final b in blocks) {
      if (b is MemoEntry && b.hasGps) pts.add(_GpsPoint.fromMemo(b));
      if (b is LocationStatus && b.latitude != null && b.longitude != null) {
        pts.add(_GpsPoint.fromLocation(b));
      }
    }
    pts.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    _noGpsTimer?.cancel();
    setState(() {
      _points = pts;
      _trackPoints = [];
      _selected = null;
      _showLines = false;
      _showTimes = false;
      _showDistances = false;
      _showTrack = false;
      _dismissedNoGpsCard = false;
      _loadedDate = date;
      _mapController = MapController();
      _zoom = 14;
    });
    if (pts.isEmpty) {
      _noGpsTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _dismissedNoGpsCard = true);
      });
    }
  }

  Future<void> _loadTrackPoints() async {
    final settings = await ref.read(settingsProvider.future);
    if (settings.savePath.isEmpty) return;

    final fp = widget.filePath;
    final currentDate = fp != null
        ? (FileNameParser.parseDate(fp.split('/').last.split('\\').last) ??
            DateTime.now())
        : DateTime.now();

    // 대기 중인 트래킹 포인트를 MD 파일에 플러시
    final pending = await TrackingService().getAndClearTrackPoints();
    if (pending.isNotEmpty) {
      final repo = ref.read(memoRepositoryProvider);
      final byDate = <DateTime, List<TrackPoint>>{};
      for (final p in pending) {
        final d = DateTime(p.timestamp.year, p.timestamp.month, p.timestamp.day);
        byDate.putIfAbsent(d, () => []).add(p);
      }
      for (final entry in byDate.entries) {
        await repo.appendTrackPoints(entry.key, entry.value, settings.savePath);
      }
    }

    if (!mounted) return;

    // 현재 날짜의 트래킹 포인트 로드
    final repo = ref.read(memoRepositoryProvider);
    final dayFile = await repo.loadDayFile(currentDate, settings.savePath);
    if (mounted) {
      final pts = dayFile?.trackPoints ?? [];
      pts.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      setState(() => _trackPoints = pts);
      _fitAllPoints();
    }
  }

  Future<Set<DateTime>> _loadExistingDates(String savePath) async {
    if (savePath.isEmpty) return {};
    final dates = <DateTime>{};
    if (SafService.isSafUri(savePath)) {
      final names = await SafService().listMdFiles(savePath);
      for (final name in names) {
        final date = FileNameParser.parseDate(name);
        if (date != null) dates.add(date);
      }
    } else {
      final dir = Directory(savePath);
      if (!await dir.exists()) return {};
      await for (final entity in dir.list()) {
        if (entity is File) {
          final name = entity.uri.pathSegments.last;
          final date = FileNameParser.parseDate(name);
          if (date != null) dates.add(date);
        }
      }
    }
    return dates;
  }

  Future<void> _pickDate() async {
    final settings = await ref.read(settingsProvider.future);
    final markedDates = await _loadExistingDates(settings.savePath);
    if (!mounted) return;

    final picked = await showDialog<DateTime>(
      context: context,
      builder: (_) => MemoDatePickerDialog(
        initialDate: _loadedDate,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        markedDates: markedDates,
      ),
    );
    if (picked == null || !mounted) return;

    final repo = ref.read(memoRepositoryProvider);
    final dayFile = await repo.loadDayFile(picked, settings.savePath);
    _applyBlocks(dayFile?.blocks ?? [], picked);
    if (mounted) {
      final pts = dayFile?.trackPoints ?? [];
      pts.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      setState(() => _trackPoints = pts);
    }
  }

  CameraFit? _cameraFit() {
    if (_points.length < 2) return null;

    final lats = _points.map((p) => p.lat);
    final lngs = _points.map((p) => p.lng);
    final minLat = lats.reduce(math.min);
    final maxLat = lats.reduce(math.max);
    final minLng = lngs.reduce(math.min);
    final maxLng = lngs.reduce(math.max);

    // 좌표가 비유효하거나 모든 점이 동일 위치인 경우
    // → CameraFit.bounds가 0÷0=NaN → toInt() 크래시 방지
    if (!minLat.isFinite || !minLng.isFinite ||
        !maxLat.isFinite || !maxLng.isFinite) return null;
    if (minLat == maxLat && minLng == maxLng) return null;

    return CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(
        _points.map((p) => LatLng(p.lat, p.lng)).toList(),
      ),
      padding: const EdgeInsets.all(52),
      maxZoom: 18,
    );
  }

  // 모든 포인트(메모+트래킹)가 한 화면에 보이도록 fit; 없으면 현재 위치
  void _fitAllPoints() {
    final allLats = [
      ..._points.map((p) => p.lat),
      ..._trackPoints.map((p) => p.lat),
    ];
    final allLngs = [
      ..._points.map((p) => p.lng),
      ..._trackPoints.map((p) => p.lng),
    ];
    if (allLats.isEmpty) {
      _moveToCurrentLocation();
      return;
    }
    if (allLats.length == 1) {
      _mapController.move(LatLng(allLats[0], allLngs[0]), 15);
      return;
    }
    final minLat = allLats.reduce(math.min);
    final maxLat = allLats.reduce(math.max);
    final minLng = allLngs.reduce(math.min);
    final maxLng = allLngs.reduce(math.max);
    if (!minLat.isFinite || !minLng.isFinite ||
        !maxLat.isFinite || !maxLng.isFinite) return;
    if (minLat == maxLat && minLng == maxLng) {
      _mapController.move(LatLng(minLat, minLng), 15);
      return;
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng)),
        padding: const EdgeInsets.all(52),
        maxZoom: 18,
      ),
    );
  }

  Future<void> _moveToCurrentLocation() async {
    try {
      Position? pos = await Geolocator.getLastKnownPosition();
      pos ??= await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.low));
      if (mounted) _mapController.move(LatLng(pos.latitude, pos.longitude), 15);
    } catch (_) {
      if (mounted) _showToastMessage('현재 위치를 가져올 수 없습니다');
    }
  }

  void _fitAllVisible(List<_PlacedPoint> placed, List<TrackPoint> track) {
    final lats = [...placed.map((p) => p.lat), ...track.map((p) => p.lat)];
    final lngs = [...placed.map((p) => p.lng), ...track.map((p) => p.lng)];
    if (lats.isEmpty) return;
    final minLat = lats.reduce(math.min);
    final maxLat = lats.reduce(math.max);
    final minLng = lngs.reduce(math.min);
    final maxLng = lngs.reduce(math.max);
    if (minLat == maxLat && minLng == maxLng) {
      _mapController.move(LatLng(minLat, minLng), 15);
      return;
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng)),
        padding: const EdgeInsets.all(52),
        maxZoom: 18,
      ),
    );
  }

  void _showToastMessage(String msg) {
    _toastTimer?.cancel();
    setState(() {
      _toastMsg = msg;
      _showToast = true;
    });
    _toastTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _showToast = false);
    });
  }

  LatLng get _initialCenter => _points.isNotEmpty
      ? LatLng(_points.first.lat, _points.first.lng)
      : const LatLng(37.5665, 126.9780);

  // zoom 레벨 기준 겹침 판정 거리 (도 단위)
  double _thresholdDeg() => 0.0003 * math.pow(2.0, 15.0 - _zoom);

  // 두 GPS 좌표 간 거리 (km, Haversine)
  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  // 화면 픽셀 → 위경도 변환
  double _pixelsToDeg(double pixels) =>
      pixels * 360.0 / (256.0 * math.pow(2.0, _zoom));

  // 겹치는 포인트를 중심점 주변에 원형으로 분산 배치
  List<_PlacedPoint> _spreadPoints() {
    if (_points.isEmpty) return [];
    final threshold = _thresholdDeg();
    final remaining = List<_GpsPoint>.from(_points);
    final result = <_PlacedPoint>[];

    while (remaining.isNotEmpty) {
      final pivot = remaining.removeAt(0);
      final group = <_GpsPoint>[pivot];
      remaining.removeWhere((p) {
        if ((p.lat - pivot.lat).abs() < threshold &&
            (p.lng - pivot.lng).abs() < threshold) {
          group.add(p);
          return true;
        }
        return false;
      });

      if (group.length == 1) {
        result.add(_PlacedPoint(group.first, group.first.lat, group.first.lng));
      } else {
        final centerLat =
            group.map((p) => p.lat).reduce((a, b) => a + b) / group.length;
        final centerLng =
            group.map((p) => p.lng).reduce((a, b) => a + b) / group.length;
        final radius = _pixelsToDeg(9.8 / math.sin(math.pi / group.length));
        for (int i = 0; i < group.length; i++) {
          final angle = (2 * math.pi * i) / group.length - math.pi / 2;
          result.add(_PlacedPoint(
            group[i],
            centerLat + radius * math.sin(angle),
            centerLng + radius * math.cos(angle),
          ));
        }
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final showTrackingButton =
        ref.watch(settingsProvider).valueOrNull?.showTrackingButton ?? true;
    final placed = _spreadPoints();
    final placedSorted = List<_PlacedPoint>.from(placed)
      ..sort((a, b) => a.point.timestamp.compareTo(b.point.timestamp));
    // 메모 타임스탬프를 파일명 날짜 + HH:mm 으로 재구성해 트래킹과 동일한 기준으로 비교
    DateTime memoFullTs(_PlacedPoint p) => DateTime(
          _loadedDate.year, _loadedDate.month, _loadedDate.day,
          p.point.timestamp.hour, p.point.timestamp.minute);
    final linePoints = () {
      if (_showTrack && _trackPoints.isNotEmpty) {
        final combined = <MapEntry<DateTime, LatLng>>[
          for (final p in placedSorted)
            MapEntry(memoFullTs(p), LatLng(p.point.lat, p.point.lng)),
          for (final p in _trackPoints)
            MapEntry(p.timestamp, LatLng(p.lat, p.lng)),
        ]..sort((a, b) => a.key.compareTo(b.key));
        return combined.map((e) => e.value).toList();
      }
      final memoOnly = [
        for (final p in placedSorted)
          MapEntry(memoFullTs(p), LatLng(p.point.lat, p.point.lng)),
      ]..sort((a, b) => a.key.compareTo(b.key));
      return memoOnly.map((e) => e.value).toList();
    }();
    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormatter.toDateString(_loadedDate)),
      ),
      body: Stack(
        children: [
          FlutterMap(
            key: ValueKey(_loadedDate),
            mapController: _mapController,
            options: MapOptions(
              initialCameraFit: _cameraFit(),
              initialCenter: _initialCenter,
              initialZoom: 15,
              onTap: (_, __) => setState(() => _selected = null),
              onPositionChanged: (camera, hasGesture) {
                if ((camera.zoom - _zoom).abs() >= 0.5) {
                  setState(() => _zoom = camera.zoom);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.sgchoisg.nakkda',
              ),
              if (_showTrack && _trackPoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _trackPoints
                          .map((p) => LatLng(p.lat, p.lng))
                          .toList(),
                      color: const Color(0xCCFF6D00),
                      strokeWidth: 2.0,
                    ),
                  ],
                ),
              if ((_showTrack || _showTimes) && _trackPoints.isNotEmpty)
                CircleLayer(
                  circles: _trackPoints
                      .map((p) => CircleMarker(
                            point: LatLng(p.lat, p.lng),
                            radius: 4,
                            color: const Color(0xCCFF6D00),
                            borderColor: Colors.white,
                            borderStrokeWidth: 1,
                          ))
                      .toList(),
                ),
              if (_showLines && linePoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: linePoints,
                      color: const Color(0xCCFF6D00),
                      strokeWidth: 2.5,
                    ),
                  ],
                ),
              if (_showLines && _showDistances && placedSorted.length >= 2)
                MarkerLayer(
                  markers: () {
                    final markers = <Marker>[];
                    for (int i = 0; i < placedSorted.length - 1; i++) {
                      final a = placedSorted[i];
                      final b = placedSorted[i + 1];
                      final km = _haversineKm(
                          a.point.lat, a.point.lng, b.point.lat, b.point.lng);
                      final t = _thresholdDeg();
                      if (km < 0.001 ||
                          ((a.point.lat - b.point.lat).abs() < t &&
                           (a.point.lng - b.point.lng).abs() < t)) continue;
                      final label = km < 1
                          ? '${(km * 1000).round()}m'
                          : '${km.toStringAsFixed(2)}km';
                      markers.add(Marker(
                        point: LatLng((a.lat + b.lat) / 2, (a.lng + b.lng) / 2),
                        width: 64,
                        height: 20,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xCC1565C0),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            label,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 10),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ));
                    }
                    return markers;
                  }(),
                ),
              MarkerLayer(
                markers: placed.map((placed) {
                  final pt = placed.point;
                  final idx = _points.indexOf(pt);
                  final isSelected = _selected == pt;
                  return Marker(
                    point: LatLng(placed.lat, placed.lng),
                    width: isSelected ? 34 : 24,
                    height: isSelected ? 34 : 24,
                    child: GestureDetector(
                      onTap: () => setState(() => _selected = pt),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: pt.isMemo
                              ? Colors.blue.shade700
                              : Colors.teal.shade600,
                          border: Border.all(
                            color: isSelected ? Colors.orange : Colors.white,
                            width: isSelected ? 3 : 2,
                          ),
                          boxShadow: const [
                            BoxShadow(blurRadius: 4, color: Color(0x55000000)),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            '${idx + 1}',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isSelected ? 11 : 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              if (_showTimes)
                MarkerLayer(
                  markers: placed.map((p) => Marker(
                    point: LatLng(p.lat, p.lng),
                    width: 56,
                    height: 36,
                    alignment: Alignment.bottomCenter,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 3, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xCC000000),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          p.point.timeLabel,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10),
                        ),
                      ),
                    ),
                  )).toList(),
                ),
              if (_showTimes && _trackPoints.isNotEmpty)
                MarkerLayer(
                  markers: _trackPoints.map((tp) {
                    final h = tp.timestamp.hour.toString().padLeft(2, '0');
                    final m = tp.timestamp.minute.toString().padLeft(2, '0');
                    return Marker(
                      point: LatLng(tp.lat, tp.lng),
                      width: 56,
                      height: 36,
                      alignment: Alignment.bottomCenter,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 3, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xCCFF6D00),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            '$h:$m',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 10),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
          // 선택된 마커 팝업
          if (_selected != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12 + MediaQuery.of(context).padding.bottom,
              child: _PointPopup(
                point: _selected!,
                savePath: _savePath,
                onClose: () => setState(() => _selected = null),
              ),
            ),
          // GPS 없음 안내 (메모 GPS + 트래킹 포인트 모두 없을 때만 표시)
          if (_points.isEmpty && _trackPoints.isEmpty && !_dismissedNoGpsCard)
            Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Card(
                    margin: const EdgeInsets.all(24),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.location_off_outlined, size: 22),
                              const SizedBox(width: 8),
                              const Text('GPS 정보가 있는 메모가 없습니다'),
                            ],
                          ),
                          TextButton(
                            onPressed: _pickDate,
                            child: const Text('다른 날짜 불러오기'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: GestureDetector(
                      onTap: () => setState(() => _dismissedNoGpsCard = true),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF9E9E9E),
                        ),
                        child: const Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // 우측 세로 툴바
          Positioned(
            top: 8,
            right: 8,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.92),
                elevation: 2,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _toolBtn(Icons.calendar_today_outlined, null, _pickDate),
                    _divider(),
                    _toolBtn(Icons.my_location, null, _moveToCurrentLocation),
                    _divider(),
                    _toolBtn(
                      Icons.schedule,
                      (placed.isNotEmpty || _trackPoints.isNotEmpty)
                          ? (_showTimes
                              ? Theme.of(context).colorScheme.primary
                              : null)
                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                      (placed.isNotEmpty || _trackPoints.isNotEmpty)
                          ? () {
                              setState(() => _showTimes = !_showTimes);
                              _showToastMessage(
                                  _showTimes ? '시간 표시 켜짐' : '시간 표시 꺼짐');
                            }
                          : () => _showToastMessage('표시할 위치 정보가 없습니다'),
                    ),
                    _divider(),
                    _toolBtn(
                      _showLines ? Icons.timeline : Icons.timeline_outlined,
                      placed.length >= 2
                          ? (_showLines
                              ? Theme.of(context).colorScheme.primary
                              : null)
                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                      placed.length >= 2
                          ? () {
                              setState(() => _showLines = !_showLines);
                              _showToastMessage(
                                  _showLines ? '메모지점 연결 켜짐' : '메모지점 연결 꺼짐');
                              if (_showLines) _fitAllVisible(placed, _showTrack ? _trackPoints : []);
                            }
                          : () => _showToastMessage('GPS 메모가 2개 이상 필요합니다'),
                    ),
                    _toolBtn(
                      Icons.straighten,
                      placed.length >= 2 && _showLines && _showDistances
                          ? Theme.of(context).colorScheme.primary
                          : (placed.length < 2 || !_showLines)
                              ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)
                              : null,
                      placed.length < 2
                          ? () => _showToastMessage('GPS 메모가 2개 이상 필요합니다')
                          : !_showLines
                              ? () => _showToastMessage('메모지점 연결을 먼저 켜세요')
                              : () {
                                  setState(() => _showDistances = !_showDistances);
                                  _showToastMessage(
                                      _showDistances ? '거리 표시 켜짐' : '거리 표시 꺼짐');
                                },
                    ),
                    if (showTrackingButton) ...[
                      _divider(),
                      _toolBtn(
                        Icons.route,
                        _trackPoints.isNotEmpty
                            ? (_showTrack
                                ? Theme.of(context).colorScheme.primary
                                : null)
                            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                        _trackPoints.isNotEmpty
                            ? () {
                                final nowOn = !_showTrack;
                                setState(() => _showTrack = nowOn);
                                if (nowOn) _fitAllVisible(_showLines ? placed : [], _trackPoints);
                                _showToastMessage(nowOn ? '이동 경로 표시중' : '이동 경로 숨김');
                              }
                            : () => _showToastMessage('이동 경로 기록이 없습니다'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          // 버튼 상태 토스트
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _showToast ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xCC000000),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _toastMsg,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolBtn(IconData icon, Color? color, VoidCallback? onPressed) {
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        iconSize: 20,
        padding: EdgeInsets.zero,
        icon: Icon(icon, color: color),
        onPressed: onPressed,
      ),
    );
  }

  Widget _divider() =>
      const Divider(height: 1, thickness: 1, indent: 6, endIndent: 6);
}

// ── 분산 배치 포인트 모델 ──────────────────────────────────

class _PlacedPoint {
  final _GpsPoint point;
  final double lat;
  final double lng;
  const _PlacedPoint(this.point, this.lat, this.lng);
}

// ── GPS 포인트 모델 ─────────────────────────────────────────

class _GpsPoint {
  final DateTime timestamp;
  final double lat;
  final double lng;
  final bool isMemo;
  final String? text;
  final String? photoPath;
  final String? videoPath;
  final double? fishLength;
  final String? address;

  _GpsPoint.fromMemo(MemoEntry e)
      : timestamp = e.timestamp,
        lat = e.latitude!,
        lng = e.longitude!,
        isMemo = true,
        text = e.text,
        photoPath = e.photoPath,
        videoPath = e.videoPath,
        fishLength = e.fishLength,
        address = null;

  _GpsPoint.fromLocation(LocationStatus l)
      : timestamp = l.timestamp,
        lat = l.latitude!,
        lng = l.longitude!,
        isMemo = false,
        text = null,
        photoPath = null,
        videoPath = null,
        fishLength = null,
        address = l.address;

  String get timeLabel {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ── 팝업 ──────────────────────────────────────────────────

class _PointPopup extends StatelessWidget {
  final _GpsPoint point;
  final String savePath;
  final VoidCallback onClose;

  const _PointPopup({
    required this.point,
    required this.savePath,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 헤더
            Row(
              children: [
                Icon(
                  point.isMemo ? Icons.chat_bubble : Icons.location_on,
                  size: 15,
                  color: point.isMemo
                      ? Colors.blue.shade700
                      : Colors.teal.shade600,
                ),
                const SizedBox(width: 6),
                Text(
                  point.timeLabel,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: onClose,
                  child: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 내용
            if (point.address != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('📍 ${point.address}',
                    style: const TextStyle(fontSize: 13)),
              ),
            if (point.photoPath != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: SafImage(
                  photoPath: point.photoPath!,
                  savePath: savePath,
                  height: 80,
                  fit: BoxFit.cover,
                ),
              ),
            if (point.videoPath != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: VideoPlayerWidget(
                  videoPath: point.videoPath!,
                  height: 80,
                ),
              ),
            if (point.text != null && point.text!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  point.text!,
                  style: const TextStyle(fontSize: 14),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (point.fishLength != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '📏 ${point.fishLength!.toStringAsFixed(1)}cm',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

