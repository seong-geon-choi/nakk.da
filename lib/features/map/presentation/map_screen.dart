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

  @override
  void initState() {
    super.initState();
    _loadFromToday();
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
    final dir = Directory(savePath);
    if (!await dir.exists()) return {};
    final dates = <DateTime>{};
    await for (final entity in dir.list()) {
      if (entity is File) {
        final name = entity.uri.pathSegments.last;
        final date = FileNameParser.parseDate(name);
        if (date != null) dates.add(date);
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
      builder: (_) => _DatePickerDialog(
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
                onClose: () => setState(() => _selected = null),
                onConnect: () => setState(() {
                  _showLines = !_showLines;
                  _selected = null;
                }),
                linesActive: _showLines,
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
}

// ── GPS 포인트 모델 ─────────────────────────────────────────

class _GpsPoint {
  final DateTime timestamp;
  final double lat;
  final double lng;
  final bool isMemo;
  final String? text;
  final String? photoPath;
  final double? fishLength;
  final String? address;

  _GpsPoint.fromMemo(MemoEntry e)
      : timestamp = e.timestamp,
        lat = e.latitude!,
        lng = e.longitude!,
        isMemo = true,
        text = e.text,
        photoPath = e.photoPath,
        fishLength = e.fishLength,
        address = null;

  _GpsPoint.fromLocation(LocationStatus l)
      : timestamp = l.timestamp,
        lat = l.latitude!,
        lng = l.longitude!,
        isMemo = false,
        text = null,
        photoPath = null,
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
  final VoidCallback onClose;
  final VoidCallback onConnect;
  final bool linesActive;

  const _PointPopup({
    required this.point,
    required this.onClose,
    required this.onConnect,
    required this.linesActive,
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
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => Scaffold(
                      backgroundColor: Colors.black,
                      appBar: AppBar(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                      ),
                      body: Center(
                        child: InteractiveViewer(
                          child: Image.file(
                            File(point.photoPath!),
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.broken_image,
                              color: Colors.white,
                              size: 64,
                            ),
                          ),
                        ),
                      ),
                    ),
                  )),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(
                      File(point.photoPath!),
                      height: 80,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(
                        height: 40,
                        child: Center(child: Icon(Icons.broken_image)),
                      ),
                    ),
                  ),
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
            const SizedBox(height: 4),
            // 버튼
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: onConnect,
                  icon: Icon(
                    linesActive ? Icons.timeline : Icons.timeline_outlined,
                    size: 16,
                  ),
                  label:
                      Text(linesActive ? '연결 해제' : '연결'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── 날짜 선택 다이얼로그 (파일 있는 날 점 표시) ──────────────────

class _DatePickerDialog extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final Set<DateTime> markedDates;

  const _DatePickerDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.markedDates,
  });

  @override
  State<_DatePickerDialog> createState() => _DatePickerDialogState();
}

class _DatePickerDialogState extends State<_DatePickerDialog> {
  late DateTime _month;
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.initialDate.year, widget.initialDate.month);
    _selected = widget.initialDate;
  }

  bool _isMarked(DateTime date) =>
      widget.markedDates.contains(DateTime(date.year, date.month, date.day));

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final daysInMonth =
        DateUtils.getDaysInMonth(_month.year, _month.month);
    final leadingBlanks =
        DateTime(_month.year, _month.month, 1).weekday - 1; // 월=0
    final today = DateTime.now();
    final prevMonth = DateTime(_month.year, _month.month - 1);
    final nextMonth = DateTime(_month.year, _month.month + 1);
    final canBack = !prevMonth
        .isBefore(DateTime(widget.firstDate.year, widget.firstDate.month));
    final canForward = !nextMonth
        .isAfter(DateTime(widget.lastDate.year, widget.lastDate.month));

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 월 이동 헤더
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: canBack
                      ? () => setState(
                          () => _month = DateTime(_month.year, _month.month - 1))
                      : null,
                ),
                Expanded(
                  child: Text(
                    '${_month.year}년 ${_month.month}월',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: canForward
                      ? () => setState(
                          () => _month = DateTime(_month.year, _month.month + 1))
                      : null,
                ),
              ],
            ),
            // 요일 헤더
            Row(
              children: ['월', '화', '수', '목', '금', '토', '일']
                  .asMap()
                  .entries
                  .map((e) => Expanded(
                        child: Center(
                          child: Text(
                            e.value,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: e.key == 5
                                  ? Colors.blue.shade400
                                  : e.key == 6
                                      ? Colors.red.shade400
                                      : Colors.grey,
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 4),
            // 날짜 그리드
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 0.85,
              children: [
                ...List.generate(leadingBlanks, (_) => const SizedBox()),
                ...List.generate(daysInMonth, (i) {
                  final day = DateTime(_month.year, _month.month, i + 1);
                  final isToday = DateUtils.isSameDay(day, today);
                  final isSelected = DateUtils.isSameDay(day, _selected);
                  final isMarked = _isMarked(day);
                  final isFuture = day.isAfter(widget.lastDate);

                  return GestureDetector(
                    onTap: isFuture
                        ? null
                        : () => setState(() => _selected = day),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected
                                ? colorScheme.primary
                                : isToday
                                    ? colorScheme.primary.withAlpha(30)
                                    : null,
                          ),
                          child: Center(
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontSize: 13,
                                color: isFuture
                                    ? Colors.grey.shade300
                                    : isSelected
                                        ? Colors.white
                                        : isToday
                                            ? colorScheme.primary
                                            : null,
                                fontWeight: isToday || isSelected
                                    ? FontWeight.bold
                                    : null,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isMarked
                                ? (isSelected
                                    ? Colors.white
                                    : colorScheme.primary)
                                : Colors.transparent,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
            const SizedBox(height: 4),
            // 버튼
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소'),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _selected),
                  child: const Text('확인'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
