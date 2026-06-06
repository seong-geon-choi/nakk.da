import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../memo/domain/models/memo_entry.dart';
import '../../memo/presentation/memo_provider.dart';
import '../../location/domain/models/location_status.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/file_name_parser.dart';
import '../../../core/services/saf_service.dart';
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
  _GpsPoint? _selected;
  bool _showLines = false;
  DateTime _loadedDate = DateTime.now();
  MapController _mapController = MapController();
  double _zoom = 14;
  String _savePath = '';

  @override
  void initState() {
    super.initState();
    _loadFromToday();
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
    setState(() {
      _points = pts;
      _selected = null;
      _showLines = false;
      _loadedDate = date;
      _mapController = MapController();
      _zoom = 14;
    });
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

  LatLng get _initialCenter => _points.isNotEmpty
      ? LatLng(_points.first.lat, _points.first.lng)
      : const LatLng(37.5665, 126.9780);

  // 줌 레벨에 따른 클러스터 묶음 거리 (도 단위)
  // zoom 15 → ~0.0003° (~33m), zoom 12 → ~0.0024° (~267m)
  double _thresholdDeg() => 0.0003 * math.pow(2.0, 15.0 - _zoom);

  List<_Cluster> _buildClusters() {
    if (_points.isEmpty) return [];
    final threshold = _thresholdDeg();
    final remaining = List<_GpsPoint>.from(_points);
    final clusters = <_Cluster>[];
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
      clusters.add(_Cluster(group));
    }
    return clusters;
  }

  void _zoomToCluster(_Cluster cluster) {
    setState(() => _selected = null);
    // zoom 18 기준 임계값(~4m) 이내면 지도 확대 대신 목록 시트 표시
    if (cluster.spread < 0.0000375) {
      _showClusterSheet(cluster);
      return;
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(
          cluster.points.map((p) => LatLng(p.lat, p.lng)).toList(),
        ),
        padding: const EdgeInsets.all(100),
        maxZoom: 18,
      ),
    );
  }

  void _showClusterSheet(_Cluster cluster) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ClusterSheet(
        cluster: cluster,
        allPoints: _points,
        savePath: _savePath,
        onSelect: (point) {
          Navigator.of(context).pop();
          setState(() => _selected = point);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormatter.toDateString(_loadedDate)),
        actions: [
          if (_points.length >= 2)
            IconButton(
              icon: Icon(
                _showLines ? Icons.timeline : Icons.timeline_outlined,
                color: _showLines
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              tooltip: _showLines ? '경로 숨기기' : '경로 연결',
              onPressed: () => setState(() => _showLines = !_showLines),
            ),
          IconButton(
            icon: const Icon(Icons.calendar_today_outlined),
            tooltip: '날짜 선택',
            onPressed: _pickDate,
          ),
        ],
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
                userAgentPackageName: 'com.nakkda.nakkda',
              ),
              if (_showLines && _points.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _points
                          .map((p) => LatLng(p.lat, p.lng))
                          .toList(),
                      color: Colors.blue.shade600,
                      strokeWidth: 2.5,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: _buildClusters().map((cluster) {
                  if (cluster.isSingle) {
                    final pt = cluster.point;
                    final idx = _points.indexOf(pt);
                    final isSelected = _selected == pt;
                    return Marker(
                      point: LatLng(pt.lat, pt.lng),
                      width: isSelected ? 46 : 34,
                      height: isSelected ? 46 : 34,
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
                                fontSize: isSelected ? 14 : 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  } else {
                    // 클러스터 마커
                    return Marker(
                      point: cluster.center,
                      width: 48,
                      height: 48,
                      child: GestureDetector(
                        onTap: () => _zoomToCluster(cluster),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.orange.shade700,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [
                              BoxShadow(blurRadius: 4, color: Color(0x55000000)),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              '${cluster.points.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }
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
          // GPS 없음 안내
          if (_points.isEmpty)
            Center(
              child: Card(
                margin: const EdgeInsets.all(24),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_off_outlined, size: 40),
                      const SizedBox(height: 8),
                      const Text('GPS 정보가 있는 메모가 없습니다'),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _pickDate,
                        child: const Text('다른 날짜 불러오기'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── 클러스터 모델 ──────────────────────────────────────────

class _Cluster {
  final List<_GpsPoint> points;
  _Cluster(this.points);

  bool get isSingle => points.length == 1;
  _GpsPoint get point => points.first;

  LatLng get center {
    final lat = points.map((p) => p.lat).reduce((a, b) => a + b) / points.length;
    final lng = points.map((p) => p.lng).reduce((a, b) => a + b) / points.length;
    return LatLng(lat, lng);
  }

  // 클러스터 내 최대 좌표 편차 (도 단위)
  double get spread {
    if (points.length <= 1) return 0;
    final lats = points.map((p) => p.lat);
    final lngs = points.map((p) => p.lng);
    final latSpread = lats.reduce(math.max) - lats.reduce(math.min);
    final lngSpread = lngs.reduce(math.max) - lngs.reduce(math.min);
    return math.max(latSpread, lngSpread);
  }
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

// ── 클러스터 목록 시트 ─────────────────────────────────────────

class _ClusterSheet extends StatelessWidget {
  final _Cluster cluster;
  final List<_GpsPoint> allPoints;
  final String savePath;
  final void Function(_GpsPoint) onSelect;

  const _ClusterSheet({
    required this.cluster,
    required this.allPoints,
    required this.savePath,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final points = cluster.points;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          width: 32,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade400,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              const Icon(Icons.location_on, size: 18),
              const SizedBox(width: 6),
              Text(
                '이 위치의 기록 ${points.length}개',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.55,
          ),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: points.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 16, endIndent: 16),
            itemBuilder: (context, i) {
              final pt = points[i];
              final mapIdx = allPoints.indexOf(pt) + 1;
              return InkWell(
                onTap: () => onSelect(pt),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 지도 인덱스 번호
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: pt.isMemo
                            ? Colors.blue.shade700
                            : Colors.teal.shade600,
                        child: Text(
                          '$mapIdx',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 내용 영역
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 시간 + 어획
                            Row(
                              children: [
                                Text(pt.timeLabel,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14)),
                                if (pt.fishLength != null) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    '📏 ${pt.fishLength!.toStringAsFixed(1)}cm',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary),
                                  ),
                                ],
                              ],
                            ),
                            // 주소
                            if (pt.address != null) ...[
                              const SizedBox(height: 3),
                              Text('📍 ${pt.address}',
                                  style: const TextStyle(fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ],
                            // 텍스트
                            if (pt.text != null && pt.text!.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(pt.text!,
                                  style: const TextStyle(fontSize: 13),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis),
                            ],
                            // 사진
                            if (pt.photoPath != null) ...[
                              const SizedBox(height: 6),
                              SafImage(
                                photoPath: pt.photoPath!,
                                savePath: savePath,
                                height: 100,
                                fit: BoxFit.cover,
                              ),
                            ],
                            // 동영상
                            if (pt.videoPath != null) ...[
                              const SizedBox(height: 6),
                              VideoPlayerWidget(
                                videoPath: pt.videoPath!,
                                height: 100,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(height: bottomPad + 8),
      ],
    );
  }
}
