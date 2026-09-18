import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
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
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/ad_banner_slot.dart';
import '../../../core/widgets/check_mark.dart';

class MapScreen extends ConsumerStatefulWidget {
  final String? filePath;
  final double? targetLat; // 지정 시 해당 위치로 카메라 이동(출퇴근 지점 보기)
  final double? targetLng;
  const MapScreen({super.key, this.filePath, this.targetLat, this.targetLng});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with TickerProviderStateMixin {
  List<_GpsPoint> _points = [];
  List<TrackPoint> _trackPoints = [];
  _GpsPoint? _selected;
  bool _showLines = false;
  bool _showTimes = false;
  bool _showDistances = false;
  bool _showTrack = false;
  Timer? _noGpsTimer;
  bool _dismissedNoGpsCard = false;
  DateTime _loadedDate = DateTime.now();
  int _reloadSeq = 0; // 같은 날짜 새로고침에도 맵을 remount시켜 initialCameraFit 재적용
  MapController _mapController = MapController();
  double _zoom = 14;
  String _savePath = '';
  // 출퇴근 지점 드래그 이동 상태: 길게 눌러 이동 모드에 들어간 핀의 인덱스와
  // 드래그 중 실시간 위치. 지도 위젯 좌표 변환용 키.
  final GlobalKey _mapStackKey = GlobalKey();
  int? _draggingPin;
  LatLng? _dragLatLng;
  // 시간대 필터: 하루 중 [시작, 종료] 분(0~1440)에 해당하는 지점만 표시.
  // null이면 필터 없음(전체 표시). _showTimeFilter로 상단 바를 접고 편다.
  RangeValues? _timeFilter;
  bool _showTimeFilter = false;
  // 현재위치 버튼: 내 위치에 역펄스(바깥 원이 중심으로 붕괴)를 3초간 표시.
  LatLng? _currentLocMarker;
  Timer? _currentLocTimer;
  late final AnimationController _pulseCtrl;

  @override
  void dispose() {
    _noGpsTimer?.cancel();
    _currentLocTimer?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
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
      final savePath = ref.read(settingsProvider).valueOrNull?.savePath ?? '';
      final file =
          ref.read(dayFileProvider(todayMemoFilePath(savePath))).valueOrNull;
      _applyBlocks(file?.blocks ?? [], DateTime.now());
    }
  }

  void _applyBlocks(List<dynamic> blocks, DateTime date,
      {bool resetToggles = true, bool keepCamera = false}) {
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
      _timeFilter = null; // 날짜 변경/새로고침 시 시간 필터 초기화
      if (resetToggles) {
        _showLines = false;
        _showTimes = false;
        _showDistances = false;
        _showTrack = false;
      }
      _dismissedNoGpsCard = false;
      _loadedDate = date;
      // 새로고침(keepCamera)일 땐 맵을 remount하지 않아 현재 카메라 위치를 유지
      if (!keepCamera) {
        _reloadSeq++;
        _mapController = MapController();
        _zoom = 14;
      }
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

  // 현재 표시 중인 날짜의 메모를 디스크에서 다시 읽어옴
  Future<void> _reloadCurrentDate() async {
    final settings = await ref.read(settingsProvider.future);
    if (settings.savePath.isEmpty) return;
    final date = _loadedDate;
    final repo = ref.read(memoRepositoryProvider);
    final dayFile = await repo.loadDayFile(date, settings.savePath);
    if (!mounted) return;
    _applyBlocks(dayFile?.blocks ?? [], date,
        resetToggles: false, keepCamera: true);
    final pts = dayFile?.trackPoints ?? [];
    pts.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    setState(() => _trackPoints = pts);
    _showToastMessage('새로고침 완료');
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
        !maxLat.isFinite || !maxLng.isFinite) {
      return null;
    }
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
        !maxLat.isFinite || !maxLng.isFinite) {
      return;
    }
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
      if (!mounted) return;
      final here = LatLng(pos.latitude, pos.longitude);
      _mapController.move(here, 15);
      _showToastMessage('현재 위치로 이동했습니다');
      _showCurrentLocPulse(here);
    } catch (_) {
      if (mounted) _showToastMessage('현재 위치를 가져올 수 없습니다');
    }
  }

  /// 현재위치에 역펄스 애니메이션을 3초간 띄우고 자동으로 사라지게 한다.
  void _showCurrentLocPulse(LatLng at) {
    _currentLocTimer?.cancel();
    setState(() => _currentLocMarker = at);
    _pulseCtrl
      ..reset()
      ..repeat();
    _currentLocTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      _pulseCtrl.stop();
      setState(() => _currentLocMarker = null);
    });
  }

  void _showToastMessage(String msg) => showAppToast(context, msg);

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

  // 메모 지점을 '화면 픽셀' 기준으로 클러스터링. 가까운(≈34px 이내) 지점들을 한
  // 묶음으로 통합해, 축소 시 겹쳐 뭉치며 흰 테두리만 남는 문제를 막는다. 각 묶음은
  // 원본 _GpsPoint 목록(단독이면 1개). 연결선·이동경로는 실제 좌표로 그리므로 이
  // 통합과 무관하게 그대로 유지된다. 줌이 바뀌면(기존 리빌드) 다시 계산된다.
  List<List<_GpsPoint>> _clusterMemoPoints(List<_GpsPoint> pts) {
    if (pts.isEmpty) return const [];
    final MapCamera cam;
    try {
      cam = _mapController.camera;
    } catch (_) {
      return [for (final p in pts) [p]]; // 카메라 미준비: 개별 표시
    }
    const clusterPx = 34.0;
    final sp = [
      for (final p in pts) cam.latLngToScreenPoint(LatLng(p.lat, p.lng))
    ];
    final used = List<bool>.filled(pts.length, false);
    final clusters = <List<_GpsPoint>>[];
    for (var i = 0; i < pts.length; i++) {
      if (used[i]) continue;
      used[i] = true;
      final group = <_GpsPoint>[pts[i]];
      for (var j = i + 1; j < pts.length; j++) {
        if (used[j]) continue;
        final dx = sp[j].x - sp[i].x, dy = sp[j].y - sp[i].y;
        if (dx * dx + dy * dy <= clusterPx * clusterPx) {
          used[j] = true;
          group.add(pts[j]);
        }
      }
      clusters.add(group);
    }
    return clusters;
  }

  // 자동 경로 점이 메모/찍은 좌표와 사실상 같은 지점이면 표시를 생략한다(메모 밑에
  // 숨김). 연결선은 실제 좌표로 그대로 통과하므로 궤적에는 영향 없다.
  bool _routePointHidden(TrackPoint p, double threshold,
      List<_GpsPoint> points, List<TrackPoint> track) {
    for (final m in points) {
      if ((m.lat - p.lat).abs() < threshold &&
          (m.lng - p.lng).abs() < threshold) {
        return true;
      }
    }
    for (final m in track) {
      if (m.marked &&
          (m.lat - p.lat).abs() < threshold &&
          (m.lng - p.lng).abs() < threshold) {
        return true;
      }
    }
    return false;
  }

  // 연결선 진행 방향 화살표: 선을 '화면 픽셀' 기준 균일 간격(≈64px)으로 걸으며
  // 다음 지점 방향으로 회전한 화살촉을 놓는다. 픽셀 기준이라 확대/축소해도 화면상
  // 밀도가 일정해 지저분해지지 않는다. 너무 축소돼 경로가 짧게 뭉치면 생략.
  List<Marker> _directionArrows(List<LatLng> pts) {
    if (pts.length < 2) return const [];
    // 첫 프레임 등 카메라 미준비 시 예외가 날 수 있어 방어(다음 리빌드에 표시됨).
    final MapCamera cam;
    try {
      cam = _mapController.camera;
    } catch (_) {
      return const [];
    }
    final sp = [for (final p in pts) cam.latLngToScreenPoint(p)];
    const spacing = 64.0;
    double total = 0;
    for (var i = 0; i < sp.length - 1; i++) {
      final dx = sp[i + 1].x - sp[i].x, dy = sp[i + 1].y - sp[i].y;
      total += math.sqrt(dx * dx + dy * dy);
    }
    if (total < 90) return const []; // 과도한 축소: 화살표 숨김
    final markers = <Marker>[];
    double acc = spacing * 0.5;
    for (var i = 0; i < sp.length - 1; i++) {
      final ax = sp[i].x, ay = sp[i].y;
      final dx = sp[i + 1].x - ax, dy = sp[i + 1].y - ay;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len < 0.5) continue;
      final ang = math.atan2(dy, dx);
      var d = acc;
      while (d <= len) {
        final t = d / len;
        final ll = cam.pointToLatLng(math.Point(ax + dx * t, ay + dy * t));
        markers.add(Marker(
          point: ll,
          width: 16,
          height: 16,
          child: Center(
            child: Transform.rotate(
              angle: ang,
              child: const CustomPaint(
                size: Size(9, 9),
                painter: _DirectionArrowPainter(),
              ),
            ),
          ),
        ));
        d += spacing;
      }
      acc = d - len;
    }
    return markers;
  }

  // 단독 메모 지점 마커(번호). 탭하면 팝업 선택.
  Marker _memoMarker(_GpsPoint pt) {
    final idx = _points.indexOf(pt);
    final isSelected = _selected == pt;
    return Marker(
      point: LatLng(pt.lat, pt.lng),
      width: isSelected ? 34 : 24,
      height: isSelected ? 34 : 24,
      child: GestureDetector(
        onTap: () => setState(() => _selected = pt),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: pt.isMemo ? Colors.blue.shade700 : Colors.teal.shade600,
            border: Border.all(
              color: isSelected ? Colors.orange : Colors.white,
              width: isSelected ? 3 : 2,
            ),
            boxShadow: const [
              BoxShadow(blurRadius: 4, color: Color(0x55000000)),
            ],
          ),
          child: Center(
            child: Text('${idx + 1}',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: isSelected ? 11 : 9,
                    fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }

  // 통합 묶음(클러스터) 마커: 개수 표시. 탭하면 목록 시트.
  Marker _clusterMarker(List<_GpsPoint> group) {
    final lat = group.map((p) => p.lat).reduce((a, b) => a + b) / group.length;
    final lng = group.map((p) => p.lng).reduce((a, b) => a + b) / group.length;
    return Marker(
      point: LatLng(lat, lng),
      width: 36,
      height: 36,
      child: GestureDetector(
        onTap: () => _showClusterSheet(group),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.blue.shade800,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [
              BoxShadow(blurRadius: 5, color: Color(0x66000000)),
            ],
          ),
          child: Center(
            child: Text('${group.length}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }

  // 클러스터에 묶인 지점들의 목록 시트. 항목을 누르면 그 지점으로 이동·확대하고 선택.
  void _showClusterSheet(List<_GpsPoint> group) {
    final sorted = List<_GpsPoint>.from(group)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text('이 위치의 지점 ${sorted.length}개',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: sorted.length,
                itemBuilder: (_, i) {
                  final p = sorted[i];
                  final n = _points.indexOf(p) + 1;
                  final sub = (p.text != null && p.text!.trim().isNotEmpty)
                      ? p.text!.trim()
                      : (p.address ??
                          (p.photoPath != null
                              ? '사진'
                              : (p.videoPath != null ? '동영상' : '위치')));
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 13,
                      backgroundColor: p.isMemo
                          ? Colors.blue.shade700
                          : Colors.teal.shade600,
                      child: Text('$n',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ),
                    title: Text('${p.timeLabel}  $sub',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() => _selected = p);
                      _mapController.move(
                          LatLng(p.lat, p.lng), math.max(_zoom, 16.0));
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // 시간대 필터: ts의 시:분이 [start, end] 범위에 드는지. 필터 없으면 항상 true.
  bool _passMinute(DateTime ts) {
    final f = _timeFilter;
    if (f == null) return true;
    final m = ts.hour * 60 + ts.minute;
    return m >= f.start && m <= f.end;
  }

  // 현재 날짜 데이터(메모+트랙)의 시:분 최소·최대(분 단위). 데이터가 없거나
  // 한 시각뿐이면 null(필터 바를 띄우지 않음).
  (double, double)? _dataMinuteRange() {
    final mins = <int>[
      for (final p in _points) p.timestamp.hour * 60 + p.timestamp.minute,
      for (final p in _trackPoints) p.timestamp.hour * 60 + p.timestamp.minute,
    ];
    if (mins.isEmpty) return null;
    final lo = mins.reduce(math.min).toDouble();
    final hi = mins.reduce(math.max).toDouble();
    if (hi <= lo) return null;
    return (lo, hi);
  }

  static String _minToHm(double m) {
    final t = m.round();
    return '${(t ~/ 60).toString().padLeft(2, '0')}:'
        '${(t % 60).toString().padLeft(2, '0')}';
  }

  // 시간대 필터의 시작/종료 시각을 수동 입력(시간 선택기)으로 지정. 선택값은 데이터
  // 구간[lo,hi]으로 제한하고 시작<=종료를 유지한다. 슬라이더는 _timeFilter를 그대로
  // 반영하므로 위치도 자동으로 맞춰진다.
  Future<void> _pickFilterTime(bool isStart, double lo, double hi) async {
    final cur = _timeFilter ?? RangeValues(lo, hi);
    final base = (isStart ? cur.start : cur.end).round();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base ~/ 60, minute: base % 60),
      initialEntryMode: TimePickerEntryMode.input, // 키보드 수동 입력 우선
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    final m = (picked.hour * 60 + picked.minute).toDouble().clamp(lo, hi);
    var start = cur.start, end = cur.end;
    if (isStart) {
      start = m;
      if (start > end) end = start;
    } else {
      end = m;
      if (end < start) start = end;
    }
    setState(() => _timeFilter = RangeValues(start, end));
  }

  // 지도 길게 누르기 → 출퇴근 알림 지점 추가(최대 3개)
  Future<void> _onMapLongPress(LatLng latlng) async {
    final s = ref.read(settingsProvider).valueOrNull;
    if (s == null || !s.commuteAlarmEnabled) {
      _showToastMessage('출퇴근 알림을 먼저 켜세요 (설정 > 개발자 메뉴)');
      return;
    }
    if (!s.commuteAlarmActive) {
      _showToastMessage('지도의 알림 버튼을 켜야 지점을 추가할 수 있습니다');
      return;
    }
    if (s.commutePins.length >= 3) {
      _showToastMessage('지점은 최대 3개까지입니다');
      return;
    }
    final label = await _askPinLabel();
    if (label == null) return; // 취소
    await ref
        .read(settingsProvider.notifier)
        .addCommutePin(latlng.latitude, latlng.longitude, label: label);
    _showToastMessage('출퇴근 알림 지점 추가됨');
  }

  // 지점 추가 시 이름 입력 다이얼로그. 취소 시 null, 비워두면 빈 문자열.
  Future<String?> _askPinLabel() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('지점 이름'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '예: 집, 회사, 강남역',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('추가')),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    return result;
  }

  Future<void> _removeCommutePin(int index) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('지점 삭제'),
        content: const Text('이 출퇴근 알림 지점을 삭제할까요?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('삭제')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(settingsProvider.notifier).removeCommutePin(index);
    }
  }

  /// 드래그 중이면 실시간 위치, 아니면 저장된 지점 위치를 반환.
  LatLng _pinLatLng(int index, CommutePin pin) =>
      (index == _draggingPin && _dragLatLng != null)
          ? _dragLatLng!
          : LatLng(pin.lat, pin.lng);

  /// 지점 핀을 길게 누르면 이동 모드 진입(핀이 커지고 빨간색으로 표시됨).
  void _onPinDragStart(int index) {
    setState(() {
      _draggingPin = index;
      _dragLatLng = null; // 첫 이동 전까지는 저장된 위치 유지
    });
    _showToastMessage('드래그하여 지점 위치를 옮기세요');
  }

  /// 드래그 중: 손가락 화면 좌표를 지도 위경도로 변환해 핀을 따라 이동.
  void _onPinDragUpdate(Offset globalPosition) {
    if (_draggingPin == null) return;
    final box = _mapStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(globalPosition);
    final latlng =
        _mapController.camera.pointToLatLng(math.Point(local.dx, local.dy));
    setState(() => _dragLatLng = latlng);
  }

  /// 드래그 종료: 변경된 위치를 저장하고 이동 모드 해제.
  Future<void> _onPinDragEnd(int index) async {
    final latlng = _dragLatLng;
    setState(() {
      _draggingPin = null;
      _dragLatLng = null;
    });
    if (latlng != null) {
      await ref
          .read(settingsProvider.notifier)
          .updateCommutePinLocation(index, latlng.latitude, latlng.longitude);
      if (mounted) _showToastMessage('지점 위치를 이동했습니다');
    }
  }

  /// 이동경로/찍은 좌표를 누르면 저장 시각을 토스트로 표시한다.
  void _showTrackTime(TrackPoint p) {
    final t = p.timestamp;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final ss = t.second.toString().padLeft(2, '0');
    final label = p.marked ? '찍은 좌표' : '이동경로';
    _showToastMessage('$label 저장 시각 $hh:$mm:$ss');
  }

  /// 경로 표시 중, 탭 위치에서 화면상 가장 가까운 이동지점의 시각을 토스트로 표시.
  /// 확대하지 않아 점이 안 보이는 상태에서도 경로 선을 눌러 시간을 확인할 수 있다.
  /// 가까운 지점이 있어 표시했으면 true.
  bool _showNearestTrackTime(LatLng tapped, List<TrackPoint> track) {
    if (track.isEmpty || !_showTrack) return false;
    final MapCamera cam;
    try {
      cam = _mapController.camera;
    } catch (_) {
      return false;
    }
    final tapSp = cam.latLngToScreenPoint(tapped);
    double best = double.infinity;
    TrackPoint? nearest;
    for (final p in track) {
      final sp = cam.latLngToScreenPoint(LatLng(p.lat, p.lng));
      final dx = sp.x - tapSp.x, dy = sp.y - tapSp.y;
      final d2 = dx * dx + dy * dy;
      if (d2 < best) {
        best = d2;
        nearest = p;
      }
    }
    if (nearest != null && best <= 44 * 44) {
      _showTrackTime(nearest);
      return true;
    }
    return false;
  }

  /// 이동경로/찍은 좌표를 길게 누르면 삭제 여부를 확인하고 MD 파일에서 제거한다.
  Future<void> _confirmDeleteTrackPoint(TrackPoint p) async {
    final label = p.marked ? '찍은 좌표' : '이동경로 좌표';
    final time = DateFormatter.toTimeString(p.timestamp);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$label 삭제'),
        content: Text('$time 좌표를 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final savePath = ref.read(settingsProvider).valueOrNull?.savePath ?? '';
    if (savePath.isEmpty) return;
    final remaining = _trackPoints
        .where((q) => !(q.lat == p.lat &&
            q.lng == p.lng &&
            q.timestamp == p.timestamp &&
            q.marked == p.marked))
        .toList();
    await ref
        .read(memoRepositoryProvider)
        .replaceTrackPoints(_loadedDate, remaining, savePath);
    if (!mounted) return;
    setState(() => _trackPoints = remaining);
    _showToastMessage('$label를 삭제했습니다');
  }

  @override
  Widget build(BuildContext context) {
    final showTrackingButton =
        ref.watch(settingsProvider).valueOrNull?.showTrackingButton ?? true;
    final commuteEnabled = ref.watch(settingsProvider
        .select((s) => s.valueOrNull?.commuteAlarmEnabled ?? false));
    final commutePins = ref.watch(settingsProvider
        .select((s) => s.valueOrNull?.commutePins ?? const <CommutePin>[]));
    final commuteRadius = ref.watch(settingsProvider
        .select((s) => s.valueOrNull?.commuteRadius ?? 200));
    final commuteActive = ref.watch(settingsProvider
        .select((s) => s.valueOrNull?.commuteAlarmActive ?? true));
    // 시간대 필터 적용된 지점 목록(렌더링 전반에서 이 목록을 사용).
    final dataRange = _dataMinuteRange();
    final fPoints = _timeFilter == null
        ? _points
        : _points.where((p) => _passMinute(p.timestamp)).toList();
    final fTrack = _timeFilter == null
        ? _trackPoints
        : _trackPoints.where((p) => _passMinute(p.timestamp)).toList();
    // 라인·거리용 메모 배치는 실제 좌표 그대로(분산 없음). 마커 표시는 클러스터로.
    final placed = [for (final p in fPoints) _PlacedPoint(p, p.lat, p.lng)];
    final memoClusters = _clusterMemoPoints(fPoints);
    final markerThreshold = _thresholdDeg();
    final placedSorted = List<_PlacedPoint>.from(placed)
      ..sort((a, b) => a.point.timestamp.compareTo(b.point.timestamp));
    // 좌표 보기 연결 노드 수 = 메모 지점 + 사용자가 찍은 좌표
    final markedCount = fTrack.where((p) => p.marked).length;
    final lineNodeCount = placed.length + markedCount;
    // 메모 타임스탬프를 파일명 날짜 + HH:mm 으로 재구성해 트래킹과 동일한 기준으로 비교
    DateTime memoFullTs(_PlacedPoint p) => DateTime(
          _loadedDate.year, _loadedDate.month, _loadedDate.day,
          p.point.timestamp.hour, p.point.timestamp.minute);
    final linePoints = () {
      if (_showTrack && fTrack.isNotEmpty) {
        final combined = <MapEntry<DateTime, LatLng>>[
          for (final p in placedSorted)
            MapEntry(memoFullTs(p), LatLng(p.point.lat, p.point.lng)),
          for (final p in fTrack)
            MapEntry(p.timestamp, LatLng(p.lat, p.lng)),
        ]..sort((a, b) => a.key.compareTo(b.key));
        return combined.map((e) => e.value).toList();
      }
      // 좌표 보기(메모지점 연결)일 때도 사용자가 찍은 좌표는 함께 선으로 연결
      final memoAndMarked = [
        for (final p in placedSorted)
          MapEntry(memoFullTs(p), LatLng(p.point.lat, p.point.lng)),
        for (final p in fTrack)
          if (p.marked) MapEntry(p.timestamp, LatLng(p.lat, p.lng)),
      ]..sort((a, b) => a.key.compareTo(b.key));
      return memoAndMarked.map((e) => e.value).toList();
    }();
    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormatter.toDateString(_loadedDate)),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today_outlined),
            tooltip: '날짜 선택',
            onPressed: _pickDate,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
            onPressed: _reloadCurrentDate,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
        key: _mapStackKey,
        children: [
          FlutterMap(
            key: ValueKey('${_loadedDate.toIso8601String()}#$_reloadSeq'),
            mapController: _mapController,
            options: MapOptions(
              initialCameraFit: widget.targetLat != null ? null : _cameraFit(),
              initialCenter: widget.targetLat != null
                  ? LatLng(widget.targetLat!, widget.targetLng!)
                  : _initialCenter,
              initialZoom: widget.targetLat != null ? 16 : 15,
              onMapReady: () {
                if (widget.targetLat != null && mounted) {
                  _mapController.move(
                      LatLng(widget.targetLat!, widget.targetLng!), 16);
                }
              },
              onTap: (_, latlng) {
                // 경로 표시 중이면 탭 위치에서 가장 가까운 이동지점의 시각을 토스트로.
                if (!_showNearestTrackTime(latlng, fTrack)) {
                  setState(() => _selected = null);
                }
              },
              onLongPress: (_, latlng) => _onMapLongPress(latlng),
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
              // 출퇴근 알림 지점: 반경 원 + 핀(탭하면 삭제, 길게 눌러 드래그 이동)
              if (commuteEnabled && commuteActive && commutePins.isNotEmpty) ...[
                CircleLayer(
                  circles: [
                    for (var i = 0; i < commutePins.length; i++)
                      CircleMarker(
                        point: _pinLatLng(i, commutePins[i]),
                        radius: commuteRadius.toDouble(),
                        useRadiusInMeter: true,
                        color: const Color(0x2218A0FF),
                        borderColor: const Color(0xFF1976D2),
                        borderStrokeWidth: 2,
                      ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    for (var i = 0; i < commutePins.length; i++)
                      Marker(
                        point: _pinLatLng(i, commutePins[i]),
                        width: 40,
                        height: 40,
                        child: GestureDetector(
                          onTap: () => _removeCommutePin(i),
                          onLongPressStart: (_) => _onPinDragStart(i),
                          onLongPressMoveUpdate: (d) =>
                              _onPinDragUpdate(d.globalPosition),
                          onLongPressEnd: (_) => _onPinDragEnd(i),
                          child: Icon(
                            Icons.train,
                            color: _draggingPin == i
                                ? const Color(0xFFD32F2F)
                                : const Color(0xFF1976D2),
                            size: _draggingPin == i ? 40 : 32,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              // 메모지점 연결(_showLines)이 켜지면 linePoints가 메모+트랙을
              // 시간순 단일 선으로 그리므로, 트랙 전용 선은 중복이라 생략한다.
              if (_showTrack && !_showLines && fTrack.length >= 2) ...[
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: fTrack
                          .map((p) => LatLng(p.lat, p.lng))
                          .toList(),
                      color: const Color(0xFFFF6D00),
                      strokeWidth: 6.0,
                    ),
                  ],
                ),
                // 진행 방향 화살표(선 안, 화면 픽셀 균일 간격)
                MarkerLayer(
                  markers: _directionArrows(
                      fTrack.map((p) => LatLng(p.lat, p.lng)).toList()),
                ),
              ],
              if (_showLines && linePoints.length >= 2) ...[
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: linePoints,
                      color: const Color(0xFFFF6D00),
                      strokeWidth: 6.0,
                    ),
                  ],
                ),
                // 진행 방향 화살표(선 안, 화면 픽셀 균일 간격)
                MarkerLayer(markers: _directionArrows(linePoints)),
              ],
              // 이동경로 좌표: 길게 누르면 삭제할 수 있게 마커로 렌더(투명한 큰
              // 히트 영역 안에 작은 점). 겹칠 때 선 모양이 흐트러지지 않도록 충분히
              // 확대(줌 ≥ 15)했을 때만 표시하고, 축소 상태에선 선만 깔끔히 보인다.
              if ((_showTrack || _showTimes) && fTrack.isNotEmpty && _zoom >= 15.0)
                MarkerLayer(
                  markers: [
                    for (final p in fTrack)
                      if (!p.marked &&
                          !_routePointHidden(p, markerThreshold, fPoints, fTrack))
                        Marker(
                          point: LatLng(p.lat, p.lng),
                          width: 24,
                          height: 24,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _showTrackTime(p),
                            onLongPress: () => _confirmDeleteTrackPoint(p),
                            child: Center(
                              child: Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xCCFF6D00),
                                  border: Border.all(
                                      color: Colors.white, width: 1),
                                ),
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
              // 사용자가 '좌표 찍기'로 남긴 지점: 항상 눈에 띄는 체크 표시로 렌더.
              // 연결선(폴리라인)보다 뒤에 두어 선이 체크 표시를 덮지 않게 한다.
              if (markedCount > 0)
                MarkerLayer(
                  markers: [
                    for (final p in fTrack)
                      if (p.marked)
                        Marker(
                          point: LatLng(p.lat, p.lng),
                          width: 30,
                          height: 30,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _showTrackTime(p),
                            onLongPress: () => _confirmDeleteTrackPoint(p),
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF6A1B9A),
                                border:
                                    Border.all(color: Colors.white, width: 2),
                                boxShadow: const [
                                  BoxShadow(
                                      blurRadius: 4, color: Color(0x66000000)),
                                ],
                              ),
                              child: const Center(
                                child: CheckMark(size: 20, strokeWidth: 3.0),
                              ),
                            ),
                          ),
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
                           (a.point.lng - b.point.lng).abs() < t)) {
                        continue;
                      }
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
              // 메모 지점: 겹치면 하나의 묶음(개수) 마커로 통합. 단독이면 번호 마커.
              MarkerLayer(
                markers: [
                  for (final group in memoClusters)
                    if (group.length == 1)
                      _memoMarker(group.first)
                    else
                      _clusterMarker(group),
                ],
              ),
              // 시간 표시: 단독 지점에만(묶음은 시트에서 확인)
              if (_showTimes)
                MarkerLayer(
                  markers: [
                    for (final group in memoClusters)
                      if (group.length == 1)
                        Marker(
                          point:
                              LatLng(group.first.lat, group.first.lng),
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
                                group.first.timeLabel,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 10),
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
              if (_showTimes && fTrack.isNotEmpty)
                MarkerLayer(
                  markers: fTrack.map((tp) {
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
              // 현재위치 역펄스: 바깥 원이 중심으로 붕괴 후 점이 번쩍(3초).
              if (_currentLocMarker != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentLocMarker!,
                      width: 96,
                      height: 96,
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _pulseCtrl,
                          builder: (_, _) => CustomPaint(
                            painter: _PulsePainter(
                                _pulseCtrl.value, const Color(0xFFFF6D00)),
                          ),
                        ),
                      ),
                    ),
                  ],
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
          // 시간대 필터 바(상단): 하나의 RangeSlider로 시작·종료 시간 동시 설정.
          if (_showTimeFilter && dataRange != null)
            Positioned(
              top: 8,
              left: 8,
              right: 56,
              child: Material(
                elevation: 3,
                borderRadius: BorderRadius.circular(10),
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.95),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
                  child: () {
                    final lo = dataRange.$1;
                    final hi = dataRange.$2;
                    final cur = _timeFilter ?? RangeValues(lo, hi);
                    final start = cur.start.clamp(lo, hi);
                    final end = cur.end.clamp(lo, hi);
                    final divisions = (hi - lo).round().clamp(1, 1440);
                    final cs = Theme.of(context).colorScheme;

                    // 탭하면 시간 선택기(수동 입력)로 시각 지정하는 필드
                    Widget field(String label, double val, bool isStart) =>
                        InkWell(
                          onTap: () => _pickFilterTime(isStart, lo, hi),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(9, 5, 7, 5),
                            decoration: BoxDecoration(
                              color: cs.surface.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: cs.outlineVariant),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('$label ',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: cs.onSurfaceVariant)),
                                Text(_minToHm(val),
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(width: 3),
                                Icon(Icons.edit,
                                    size: 12, color: cs.onSurfaceVariant),
                              ],
                            ),
                          ),
                        );

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            field('시작', start, true),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 5),
                              child: Text('~'),
                            ),
                            field('종료', end, false),
                            const Spacer(),
                            if (_timeFilter != null)
                              TextButton(
                                onPressed: () =>
                                    setState(() => _timeFilter = null),
                                style: TextButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 6),
                                  minimumSize: const Size(0, 30),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text('전체',
                                    style: TextStyle(fontSize: 12)),
                              ),
                            GestureDetector(
                              onTap: () =>
                                  setState(() => _showTimeFilter = false),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.close, size: 18),
                              ),
                            ),
                          ],
                        ),
                        // 아래 슬라이더(양쪽 핸들)로 드래그 조정 — 입력값과 동기화됨
                        SizedBox(
                          height: 30,
                          child: RangeSlider(
                            min: lo,
                            max: hi,
                            divisions: divisions,
                            values: RangeValues(start, end),
                            labels: RangeLabels(
                                _minToHm(start), _minToHm(end)),
                            onChanged: (v) =>
                                setState(() => _timeFilter = v),
                          ),
                        ),
                      ],
                    );
                  }(),
                ),
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
                    // 출퇴근 알림: 설정 마스터 토글이 켜진 경우에만 노출, 추적 켜고/끄기
                    if (commuteEnabled) ...[
                      _toolBtn(
                        commuteActive
                            ? Icons.notifications_active
                            : Icons.notifications_off_outlined,
                        commuteActive
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.4),
                        () {
                          final next = !commuteActive;
                          ref
                              .read(settingsProvider.notifier)
                              .updateCommuteActive(next);
                          _showToastMessage(next ? '출퇴근 알림 켜짐' : '출퇴근 알림 꺼짐');
                        },
                      ),
                      _divider(),
                    ],
                    _toolBtn(Icons.my_location, null, _moveToCurrentLocation),
                    _divider(),
                    _toolBtn(
                      Icons.filter_alt,
                      dataRange != null
                          ? (_showTimeFilter || _timeFilter != null
                              ? Theme.of(context).colorScheme.primary
                              : null)
                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                      dataRange != null
                          ? () => setState(() => _showTimeFilter = !_showTimeFilter)
                          : () => _showToastMessage('필터할 시간 정보가 없습니다'),
                    ),
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
                      lineNodeCount >= 2
                          ? (_showLines
                              ? Theme.of(context).colorScheme.primary
                              : null)
                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                      lineNodeCount >= 2
                          ? () {
                              setState(() => _showLines = !_showLines);
                              _showToastMessage(
                                  _showLines ? '메모지점 연결 켜짐' : '메모지점 연결 꺼짐');
                            }
                          : () => _showToastMessage('연결할 지점이 2개 이상 필요합니다'),
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
        ],
      ),
          ),
          const AdBannerSlot(),
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

// 연결선 진행 방향 화살촉(오목 밑변, 흰색). 기본은 오른쪽(+x)을 향하고,
// 배치 시 Transform.rotate로 진행 방향에 맞춘다.
class _DirectionArrowPainter extends CustomPainter {
  const _DirectionArrowPainter();
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final path = ui.Path()
      ..moveTo(w * 0.94, h * 0.5) // 끝(tip)
      ..lineTo(w * 0.10, h * 0.10) // 뒤 위
      ..lineTo(w * 0.36, h * 0.5) // 밑변 오목(진행 방향으로 파임)
      ..lineTo(w * 0.10, h * 0.90) // 뒤 아래
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0x66000000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _DirectionArrowPainter oldDelegate) => false;
}

/// 현재위치 역펄스: 바깥 원 하나가 중심으로 붕괴하다 마지막에 중심 점이 번쩍.
/// [t]는 0~1(AnimationController.value). 웹 시안(implode)과 동일한 키프레임.
class _PulsePainter extends CustomPainter {
  final double t;
  final Color color;
  const _PulsePainter(this.t, this.color);

  double _lerp(double a, double b, double x) => a + (b - a) * x.clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size s) {
    final c = Offset(s.width / 2, s.height / 2);
    const baseR = 23.0; // 스케일 1일 때 반지름(지름 46px)

    // 붕괴하는 링: 스케일 2.0→0.3, 불투명도는 나타났다 마지막에 사라짐.
    final ringScale = t <= 0.78 ? _lerp(2.0, 0.3, t / 0.78) : 0.3;
    double ringOpacity;
    if (t <= 0.2) {
      ringOpacity = _lerp(0.0, 0.9, t / 0.2);
    } else if (t <= 0.78) {
      ringOpacity = _lerp(0.9, 1.0, (t - 0.2) / 0.58);
    } else if (t <= 0.82) {
      ringOpacity = _lerp(1.0, 0.0, (t - 0.78) / 0.04);
    } else {
      ringOpacity = 0.0;
    }
    if (ringOpacity > 0.01) {
      canvas.drawCircle(
          c,
          baseR * ringScale,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = color.withValues(alpha: ringOpacity));
    }

    // 중심 점: 붕괴 직후(74~82%) 번쩍 커졌다 원래대로.
    double dotScale = 1.0;
    double glow = 0.0;
    if (t >= 0.74 && t < 0.82) {
      final x = (t - 0.74) / 0.08;
      dotScale = _lerp(1.0, 1.7, x);
      glow = _lerp(0.0, 0.5, x);
    } else if (t >= 0.82) {
      dotScale = _lerp(1.7, 1.0, (t - 0.82) / 0.18);
    }
    final dotR = 6.5 * dotScale;
    if (glow > 0.01) {
      canvas.drawCircle(
          c,
          dotR + 5,
          Paint()
            ..color = color.withValues(alpha: glow)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    }
    canvas.drawCircle(c, dotR + 2, Paint()..color = Colors.white);
    canvas.drawCircle(c, dotR, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _PulsePainter old) => old.t != t;
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

