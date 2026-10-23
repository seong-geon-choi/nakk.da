import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../memo/domain/models/memo_entry.dart';
import '../../memo/presentation/memo_provider.dart';
import '../../location/domain/models/location_status.dart';
import '../../location/presentation/location_provider.dart';
import '../../tide/domain/models/tide_station.dart';
import '../../../core/widgets/catch_tide_chart.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/file_name_parser.dart';
import '../../../core/services/saf_service.dart';
import '../../../core/services/tracking_service.dart';
import '../../../core/services/catch_events_service.dart';
import '../../../core/widgets/media_gallery_screen.dart';
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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  StreamSubscription<void>? _catchSub; // 조과 집계 변경 이벤트 구독
  List<_GpsPoint> _points = [];
  List<TrackPoint> _trackPoints = [];
  _GpsPoint? _selected;
  bool _showLines = false;
  bool _showTimes = false;
  bool _showDistances = false;
  bool _showTrack = false;
  bool _showMemoPoints = true; // 메모 지점(파란 마커) 표시 여부. 끄면 숨김
  bool _showCatchChart = false; // 조과 보기: 조위+시간당 조과 차트 패널
  bool _showCatchPoints = false; // 조과 마커 표시(그래프 창과 독립)
  Set<String> _hiddenCatchSpecies = {}; // 차트 범례에서 숨긴 어종(지도 마커도 숨김)
  // 조과 차트 패널 위치(드래그 이동, prefs 저장). left=null이면 기본(하단 중앙),
  // bottom=0이면 광고 바로 위에 붙음. 위로 드래그하면 bottom 증가.
  double? _chartLeft;
  double? _chartBottom;
  // 우측 세로 툴바: 가로는 우측 가장자리 고정, 세로 위치만 드래그·저장. null이면 기본(상단).
  double? _toolTop;
  static const double _toolW = 40; // 툴바 폭(_toolBtn SizedBox 폭과 동일)
  List<TideEvent> _dayTides = const []; // 그날 현황 블록의 만조/간조(조위 곡선용)
  bool _tideFetchTried = false; // 물때 자동 수집 1회 시도 플래그(날짜 바뀌면 리셋)
  Map<String, List<DateTime>> _catchBySpecies = const {}; // 어종별 기록 시각(시간당 조과 막대)
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
    WidgetsBinding.instance.removeObserver(this);
    _catchSub?.cancel();
    _noGpsTimer?.cancel();
    _currentLocTimer?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    _loadFromToday();
    _loadTrackPoints();
    _loadPanelPositions();
    // 알림 +1·블루투스 리모컨으로 집계가 바뀌면(네이티브) 지도/차트 즉시 갱신.
    _catchSub = CatchEventsService.instance.onCountsChanged
        .listen((_) => _onCatchCountsChanged());
    ref.read(settingsProvider.future).then((s) {
      if (mounted) setState(() => _savePath = s.savePath);
    });
  }

  // 화면 꺼진 동안(백그라운드) 눌린 분은 복귀(resume) 시 반영.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onCatchCountsChanged();
  }

  // 조과 집계 변경 반영: 오늘 날짜를 보고 있을 때만 조용히 다시 읽는다
  // (블루투스/알림 기록은 항상 '오늘' 파일에 적재되므로).
  void _onCatchCountsChanged() {
    final n = DateTime.now();
    final d = _loadedDate;
    if (d.year == n.year && d.month == n.month && d.day == n.day) {
      _reloadCurrentDate(silent: true);
    }
  }

  // ── 패널/툴바 위치 저장·복원 ─────────────────────────────
  static const _kToolLeft = 'map_tool_left';
  static const _kToolTop = 'map_tool_top';
  static const _kChartLeft = 'map_chart_left';
  static const _kChartBottom = 'map_chart_bottom';

  Future<void> _loadPanelPositions() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kToolLeft); // 가로 위치는 더 이상 쓰지 않음(우측 고정) — 옛 값 정리
    if (!mounted) return;
    setState(() {
      _toolTop = p.getDouble(_kToolTop);
      _chartLeft = p.getDouble(_kChartLeft);
      _chartBottom = p.getDouble(_kChartBottom);
    });
  }

  Future<void> _savePanelPositions() async {
    final p = await SharedPreferences.getInstance();
    Future<void> put(String k, double? v) async =>
        v == null ? p.remove(k) : p.setDouble(k, v);
    await put(_kToolTop, _toolTop);
    await put(_kChartLeft, _chartLeft);
    await put(_kChartBottom, _chartBottom);
  }

  /// 지도 스택(_mapStackKey)의 실제 크기. 첫 프레임 등 미측정 시 화면 크기로 근사.
  Size _stackSize(BuildContext context) {
    final box = _mapStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) return box.size;
    return MediaQuery.of(context).size;
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

  // 좌표·시각이 같은 지점을 찾아 되돌린다(재적용 후 선택 유지용).
  _GpsPoint? _findPoint(List<_GpsPoint> pts, _GpsPoint t) {
    for (final p in pts) {
      if (p.timestamp == t.timestamp && p.lat == t.lat && p.lng == t.lng) {
        return p;
      }
    }
    return null;
  }

  void _applyBlocks(List<dynamic> blocks, DateTime date,
      {bool resetToggles = true,
      bool keepCamera = false,
      bool preserveSelection = false}) {
    // 재적용 후에도 열린 팝업을 유지하려면 이전 선택을 좌표·시각으로 되찾는다.
    final prevSel = preserveSelection ? _selected : null;
    final pts = <_GpsPoint>[];
    final catchBySpecies = <String, List<DateTime>>{};
    List<TideEvent> dayTides = const [];
    for (final b in blocks) {
      if (b is MemoEntry) {
        if (b.hasGps) pts.add(_GpsPoint.fromMemo(b));
        // 조과(어종 기록): 수동 입력·알림 기록 모두 어종별 시간당 집계 대상
        final sp = b.fishSpecies?.trim();
        if (sp != null && sp.isNotEmpty) {
          catchBySpecies.putIfAbsent(sp, () => []).add(b.timestamp);
        }
      }
      if (b is LocationStatus) {
        // 현장정보 수집(위치상태) 지점은 지도 마커로 표시하지 않는다(요청).
        // 조위 곡선용 tides만 추출해 사용한다.
        if (dayTides.isEmpty && b.tides.isNotEmpty) dayTides = b.tides;
      }
    }
    pts.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    _noGpsTimer?.cancel();
    setState(() {
      _points = pts;
      _catchBySpecies = catchBySpecies;
      // 파일에 물때가 있으면 그걸 쓰고, 없으면 같은 날 재적용(리로드) 시엔 자동
      // 수집해 둔 _dayTides를 보존한다. 날짜가 바뀌면(keepCamera=false) 비운다.
      _dayTides = dayTides.isNotEmpty
          ? dayTides
          : (keepCamera ? _dayTides : const <TideEvent>[]);
      _trackPoints = [];
      _selected = prevSel == null ? null : _findPoint(pts, prevSel);
      _timeFilter = null; // 날짜 변경/새로고침 시 시간 필터 초기화
      if (resetToggles) {
        _showLines = false;
        _showTimes = false;
        _showDistances = false;
        _showTrack = false;
        _showMemoPoints = true;
        _showCatchChart = false;
        _showCatchPoints = false;
        _tideFetchTried = false; // 새 날짜 → 물때 자동 수집 재시도 허용
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

  // 현재 표시 중인 날짜의 메모를 디스크에서 다시 읽어옴.
  // silent=true면 토스트 없이(자동 갱신), 선택(팝업)은 유지한다.
  Future<void> _reloadCurrentDate({bool silent = false}) async {
    final settings = await ref.read(settingsProvider.future);
    if (settings.savePath.isEmpty) return;
    final date = _loadedDate;
    final repo = ref.read(memoRepositoryProvider);
    final dayFile = await repo.loadDayFile(date, settings.savePath);
    if (!mounted) return;
    _applyBlocks(dayFile?.blocks ?? [], date,
        resetToggles: false, keepCamera: true, preserveSelection: true);
    final pts = dayFile?.trackPoints ?? [];
    pts.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    setState(() => _trackPoints = pts);
    if (!silent) _showToastMessage('새로고침 완료');
  }

  // 조위 그래프에 쓸 물때가 없으면(현장정보 미기록 등) 자동으로 수집한다.
  // 기준 위치: 그날 지점(GPS) 우선, 없으면 현재 위치. 날짜당 1회만 시도.
  Future<void> _ensureDayTides() async {
    if (!mounted || _dayTides.isNotEmpty || _tideFetchTried) return;
    _tideFetchTried = true;
    double? lat;
    double? lng;
    if (_points.isNotEmpty) {
      lat = _points.first.lat;
      lng = _points.first.lng;
    } else {
      try {
        final pos = await Geolocator.getLastKnownPosition() ??
            await Geolocator.getCurrentPosition();
        lat = pos.latitude;
        lng = pos.longitude;
      } catch (_) {}
    }
    if (lat == null || lng == null) return;
    try {
      // 메모 현장정보와 동일한 수집(역지오코딩·기온/바람·물때·수온·관측소).
      final fresh = await ref
          .read(locationProvider.notifier)
          .buildEnrichedAt(lat: lat, lng: lng, date: _loadedDate);
      if (!mounted || fresh.tides.isEmpty) return;
      setState(() => _dayTides = fresh.tides);
      await _persistDayTides(fresh);
    } catch (_) {}
  }

  // 자동 수집한 현장정보를 그날 파일에 저장(다음에 열 때 재수집 불필요).
  // 현장정보가 있으면 비어있는 항목만 채워 교체(기존값 보존), 없으면 새로 만든다.
  Future<void> _persistDayTides(LocationStatus fresh) async {
    try {
      final savePath = ref.read(settingsProvider).valueOrNull?.savePath ?? '';
      if (savePath.isEmpty) return;
      final repo = ref.read(memoRepositoryProvider);
      final dayFile = await repo.loadDayFile(_loadedDate, savePath);
      final blocks = dayFile?.blocks ?? const [];
      var locIdx = -1;
      for (var i = 0; i < blocks.length; i++) {
        if (blocks[i] is LocationStatus) {
          locIdx = i;
          break;
        }
      }
      if (locIdx >= 0) {
        final e = blocks[locIdx] as LocationStatus;
        if (e.tides.isNotEmpty) return; // 이미 물때가 있으면 건드리지 않음
        // 기존 비어있는 항목만 수집값으로 채운다(기존 주소/시각 등 보존).
        final merged = LocationStatus(
          timestamp: e.timestamp,
          latitude: e.latitude ?? fresh.latitude,
          longitude: e.longitude ?? fresh.longitude,
          address: e.address ?? fresh.address,
          temperature: e.temperature ?? fresh.temperature,
          tideName: e.tideName ?? fresh.tideName,
          tideTime: e.tideTime ?? fresh.tideTime,
          waterTemp: e.waterTemp ?? fresh.waterTemp,
          stationName: e.stationName ?? fresh.stationName,
          stationDistance: e.stationDistance ?? fresh.stationDistance,
          isMove: e.isMove,
          windSpeed: e.windSpeed ?? fresh.windSpeed,
          windDeg: e.windDeg ?? fresh.windDeg,
          weatherCode: e.weatherCode ?? fresh.weatherCode,
          tides: fresh.tides,
        );
        await repo.replaceBlock(_loadedDate, locIdx, merged, savePath);
      } else {
        await repo.appendLocationBlock(_loadedDate, fresh, savePath);
      }
    } catch (_) {}
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

  /// 지도에 표시된 그날 지점들의 미디어(사진·동영상)를 시간순으로 모은다.
  /// 좌표 팝업에서 사진을 탭하면 이 목록으로 전체화면 갤러리를 연다.
  List<MediaGalleryItem> _dayMediaItems() {
    final sorted = _points.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return [
      for (final p in sorted)
        if (p.photoPath != null)
          MediaGalleryItem(path: p.photoPath!, isVideo: false)
        else if (p.videoPath != null)
          MediaGalleryItem(path: p.videoPath!, isVideo: true),
    ];
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
  // 클러스터 병합 키: 같은 키끼리만 하나의 묶음으로 합친다.
  // 조과는 어종별로(어종이 다르면 안 합쳐짐), 메모는 메모끼리, 현장정보는 그들끼리.
  String _clusterKey(_GpsPoint p) {
    if (p.isCatch) return 'c:${p.species ?? ''}';
    return p.isMemo ? 'm' : 'l';
  }

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
      final key = _clusterKey(pts[i]);
      for (var j = i + 1; j < pts.length; j++) {
        if (used[j]) continue;
        if (_clusterKey(pts[j]) != key) continue; // 같은 종류만 병합
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

  // 묶음의 시간 라벨: 단독이면 그 시각, 여러 개면 "첫~막" 범위(같으면 단일).
  // [off]는 펼친 마커의 부채꼴 이동량(라벨도 같이 이동).
  _TimeLabel _groupLabel(List<_GpsPoint> g, [Offset off = Offset.zero]) {
    final lat = g.map((p) => p.lat).reduce((a, b) => a + b) / g.length;
    final lng = g.map((p) => p.lng).reduce((a, b) => a + b) / g.length;
    if (g.length == 1) return _TimeLabel(lat, lng, g.first.timeLabel, off);
    final sorted = g.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final first = sorted.first.timeLabel, last = sorted.last.timeLabel;
    return _TimeLabel(lat, lng, first == last ? first : '$first~$last', off);
  }

  /// 같은 자리에 겹친 서로 다른 '묶음'들을 항상 부채꼴로 펼쳐 마커를 만든다.
  /// (같은 어종은 이미 하나의 묶음이므로, 펼침 대상은 서로 다른 종류/어종뿐.)
  /// [labelOut]에는 단독·묶음·펼친 지점 모두 시간 라벨을 담는다(펼친 건 오프셋 포함).
  void _layoutClusters(
      List<List<_GpsPoint>> clusters, List<Marker> out, List<_TimeLabel> labelOut) {
    MapCamera? cam;
    try {
      cam = _mapController.camera;
    } catch (_) {}
    if (cam == null) {
      for (final g in clusters) {
        out.add(g.length == 1 ? _memoMarker(g.first) : _clusterMarker(g));
        labelOut.add(_groupLabel(g));
      }
      return;
    }
    final centers = [
      for (final g in clusters)
        cam.latLngToScreenPoint(LatLng(g.first.lat, g.first.lng))
    ];
    const px = 34.0;
    final used = List<bool>.filled(clusters.length, false);
    for (var i = 0; i < clusters.length; i++) {
      if (used[i]) continue;
      used[i] = true;
      final bundle = <int>[i];
      for (var j = i + 1; j < clusters.length; j++) {
        if (used[j]) continue;
        final dx = centers[j].x - centers[i].x, dy = centers[j].y - centers[i].y;
        if (dx * dx + dy * dy <= px * px) {
          used[j] = true;
          bundle.add(j);
        }
      }
      if (bundle.length == 1) {
        final g = clusters[i];
        out.add(g.length == 1 ? _memoMarker(g.first) : _clusterMarker(g));
        labelOut.add(_groupLabel(g));
        continue;
      }
      // 겹친 서로 다른 종류: 항상 부채꼴로 분리해 각 색이 보이게 한다.
      const r = 22.0;
      for (var b = 0; b < bundle.length; b++) {
        final ang = -math.pi / 2 + 2 * math.pi * b / bundle.length;
        final off = Offset(r * math.cos(ang), r * math.sin(ang));
        final g = clusters[bundle[b]];
        out.add(g.length == 1 ? _memoMarker(g.first, off) : _clusterMarker(g, off));
        labelOut.add(_groupLabel(g, off)); // 펼친 마커 위에 시각/범위 라벨
      }
    }
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

  // 조과 어종 색: 조위·조과 차트 범례와 동일(같은 팔레트·같은 어종 순서).
  // 어종 순서 = _catchBySpecies의 비어있지 않은 키 순서(차트의 allSpecies와 일치).
  Color _catchColor(String? species) {
    final ordered = _catchBySpecies.keys
        .where((s) => (_catchBySpecies[s] ?? const []).isNotEmpty)
        .toList();
    final i = species == null ? -1 : ordered.indexOf(species);
    if (i < 0) return Colors.red.shade600; // 매칭 안 되면 기본 조과색
    return CatchTideChart.palette[i % CatchTideChart.palette.length];
  }

  // 지점 종류별 색: 조과(🎣)=어종별(차트 범례색), 메모=파랑, 현장정보(위치)=청록.
  Color _pointColor(_GpsPoint pt) {
    if (pt.isCatch) return _catchColor(pt.species);
    return pt.isMemo ? Colors.blue.shade700 : Colors.teal.shade600;
  }

  // 단독 지점 마커(번호 없음, 색으로 종류 구분). 탭하면 팝업 선택.
  // [off]가 주어지면 겹침 펼침용으로 화면 픽셀만큼 이동(줌/이동과 무관).
  Marker _memoMarker(_GpsPoint pt, [Offset off = Offset.zero]) {
    final isSelected = _selected == pt;
    final size = isSelected ? 26.0 : 18.0;
    final box = off == Offset.zero ? size : 2 * (off.distance + size);
    return Marker(
      point: LatLng(pt.lat, pt.lng),
      width: box,
      height: box,
      child: Center(
        child: Transform.translate(
          offset: off,
          child: GestureDetector(
            onTap: () => setState(() => _selected = pt),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _pointColor(pt),
                border: Border.all(
                  color: isSelected ? Colors.orange : Colors.white,
                  width: isSelected ? 3 : 2,
                ),
                boxShadow: const [
                  BoxShadow(blurRadius: 4, color: Color(0x55000000)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 통합 묶음(클러스터) 마커: 개수 표시. 탭하면 목록 시트.
  // 같은 종류만 묶이므로 색은 그 종류색(조과=어종색, 메모=파랑, 현장정보=청록).
  Marker _clusterMarker(List<_GpsPoint> group, [Offset off = Offset.zero]) {
    final lat = group.map((p) => p.lat).reduce((a, b) => a + b) / group.length;
    final lng = group.map((p) => p.lng).reduce((a, b) => a + b) / group.length;
    final first = group.first;
    final clusterColor = first.isCatch
        ? _catchColor(first.species)
        : (first.isMemo ? Colors.blue.shade800 : Colors.teal.shade700);
    const base = 36.0;
    final box = off == Offset.zero ? base : 2 * (off.distance + base);
    return Marker(
      point: LatLng(lat, lng),
      width: box,
      height: box,
      child: Center(
        child: Transform.translate(
          offset: off,
          child: GestureDetector(
            onTap: () => _showClusterSheet(group),
            child: Container(
              width: base,
              height: base,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: clusterColor,
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
        ),
      ),
    );
  }

  // 클러스터에 묶인 지점들의 목록 시트. 항목을 누르면 그 지점으로 이동·확대하고 선택.
  /// 클러스터 목록의 지점 설명: 조과면 어종, 메모면 그 내용(없으면 사진/동영상/주소).
  String _pointSubtitle(_GpsPoint p) {
    if (p.isCatch) {
      final sp = p.species?.trim();
      return (sp != null && sp.isNotEmpty) ? sp : '조과';
    }
    if (p.text != null && p.text!.trim().isNotEmpty) return p.text!.trim();
    if (p.photoPath != null) return '사진';
    if (p.videoPath != null) return '동영상';
    return p.address ?? '메모';
  }

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
                  final sub = _pointSubtitle(p);
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 8,
                      backgroundColor: _pointColor(p),
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
    // 메모 지점 숨김 시 isMemo 지점 제외. 시간대 필터도 함께 적용.
    // 조과(🎣) 지점은 '조과 마커'(_showCatchPoints) 토글로 표시 — 그래프 창과 독립.
    final fPoints = _points.where((p) {
      if (p.isCatch &&
          (!_showCatchPoints || _hiddenCatchSpecies.contains(p.species))) {
        return false;
      }
      if (!_showMemoPoints && p.isMemo) return false;
      return _passMinute(p.timestamp);
    }).toList();
    final fTrack = _timeFilter == null
        ? _trackPoints
        : _trackPoints.where((p) => _passMinute(p.timestamp)).toList();
    // 라인·거리용 메모 배치는 실제 좌표 그대로(분산 없음). 마커 표시는 클러스터로.
    final placed = [for (final p in fPoints) _PlacedPoint(p, p.lat, p.lng)];
    final memoClusters = _clusterMemoPoints(fPoints);
    // 같은 자리에 겹친 서로 다른 종류는 항상 부채꼴로 펼친다. labelPoints = 겹치지
    // 않은 단독 지점(시간 라벨 대상).
    final clusterMarkers = <Marker>[];
    final labelPoints = <_TimeLabel>[];
    _layoutClusters(memoClusters, clusterMarkers, labelPoints);
    final markerThreshold = _thresholdDeg();
    final placedSorted = List<_PlacedPoint>.from(placed)
      ..sort((a, b) => a.point.timestamp.compareTo(b.point.timestamp));
    final markedCount = fTrack.where((p) => p.marked).length;
    // 메모 타임스탬프를 파일명 날짜 + HH:mm 으로 재구성해 트래킹과 동일한 기준으로 비교
    DateTime memoFullTs(_PlacedPoint p) => DateTime(
          _loadedDate.year, _loadedDate.month, _loadedDate.day,
          p.point.timestamp.hour, p.point.timestamp.minute);
    // 연결선: 현재 '보이는' 모든 마커(메모·조과·현황 + 이동경로)를 시간순 단일 선으로.
    // 이동경로 점은 route 토글(_showTrack) ON일 때만 노드로 포함(찍은 좌표는 항상 포함).
    final lineNodes = <MapEntry<DateTime, LatLng>>[
      for (final p in placedSorted)
        MapEntry(memoFullTs(p), LatLng(p.point.lat, p.point.lng)),
      for (final p in fTrack)
        if (_showTrack || p.marked) MapEntry(p.timestamp, LatLng(p.lat, p.lng)),
    ]..sort((a, b) => a.key.compareTo(b.key));
    final linePoints = lineNodes.map((e) => e.value).toList();
    final lineNodeCount = lineNodes.length; // 연결 가능한 보이는 노드 수
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
              // 연결(_showLines): 보이는 모든 마커를 시간순 단일 선으로 연결.
              // 이동경로만 켜진 경우엔 트랙 점들을 잇는 기존 경로선과 동일해진다.
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
              // 지점 마커: 같은 종류는 묶음(개수), 겹친 다른 종류는 부채꼴로 펼침.
              MarkerLayer(markers: clusterMarkers),
              // 시간 표시: 겹치지 않은 단독 지점에만(묶음·펼침 지점은 시트/선택으로 확인)
              if (_showTimes)
                MarkerLayer(
                  markers: [
                    for (final p in labelPoints)
                      Marker(
                        point: LatLng(p.lat, p.lng),
                        width: 220,
                        height: 160,
                        alignment: Alignment.center,
                        // 단독은 마커 위(−26px). 펼친 마커는 그 부채꼴 '방향 바깥쪽'으로
                        // 더 밀어(×2.5) 라벨끼리 마커처럼 벌어지게 한다(겹침 방지).
                        child: Center(
                          child: Transform.translate(
                            offset: p.offset == Offset.zero
                                ? const Offset(0, -26)
                                : p.offset * 2.5,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 3, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xCC000000),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                p.text,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 10),
                              ),
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
          // 조과 보기 패널: 조위 사인곡선 + 시간당 조과 막대. 제목줄을 잡고 드래그 이동.
          if (_showCatchChart) _buildChartPanel(context),
          // 선택된 마커 팝업
          if (_selected != null)
            Positioned(
              left: 12,
              right: 12,
              // 이 Stack은 광고배너(=내비바 inset 예약) 위에 있으므로 여기서 inset을
              // 또 더하면 이중이 된다. 12만 띄운다.
              bottom: 12,
              child: _PointPopup(
                point: _selected!,
                savePath: _savePath,
                galleryItems: _dayMediaItems(),
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
          // 우측 세로 툴바. 가로는 화면 우측 가장자리에 고정(세이프에어리어 반영).
          // 핸들을 끌면 세로 위치만 이동하고 저장·재사용. 미측정 첫 프레임은 화면 크기로 근사.
          Positioned(
            right: 4 + MediaQuery.of(context).padding.right,
            top: (_toolTop ?? (8 + MediaQuery.of(context).padding.top))
                .clamp(0.0, _stackSize(context).height - 40),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.92),
                elevation: 2,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 드래그 핸들: 끌어서 버튼바를 위/아래로 이동(마지막 위치 저장·재사용)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (d) {
                        final ts = _stackSize(context);
                        final curTop = _toolTop ??
                            (8 + MediaQuery.of(context).padding.top);
                        setState(() {
                          _toolTop = (curTop + d.delta.dy)
                              .clamp(0.0, ts.height - 40);
                        });
                      },
                      onPanEnd: (_) => _savePanelPositions(),
                      child: SizedBox(
                        width: _toolW,
                        height: 22,
                        child: Icon(Icons.drag_indicator,
                            size: 16,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.7)),
                      ),
                    ),
                    const Divider(
                        height: 1, thickness: 1, indent: 6, endIndent: 6),
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
                    // ── 마커 표시(종류별 켜기) ─────────────────
                    _toolBtn(
                      _showMemoPoints ? Icons.location_on : Icons.location_off,
                      _points.any((p) => p.isMemo)
                          ? (_showMemoPoints
                              ? Theme.of(context).colorScheme.primary
                              : null)
                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                      _points.any((p) => p.isMemo)
                          ? () {
                              setState(() => _showMemoPoints = !_showMemoPoints);
                              _showToastMessage(
                                  _showMemoPoints ? '메모 지점 표시' : '메모 지점 숨김');
                            }
                          : () => _showToastMessage('메모 지점이 없습니다'),
                    ),
                    if (showTrackingButton)
                      _toolBtn(
                        Icons.route, // 이동경로 점 표시(선은 '연결'로 그림)
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
                    _divider(),
                    // ── 연결(보이는 마커를 시간순 한 줄로) + 거리 ──
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
                                  _showLines ? '마커 연결 켜짐' : '마커 연결 꺼짐');
                            }
                          : () => _showToastMessage('연결할 마커가 2개 이상 필요합니다'),
                    ),
                    _toolBtn(
                      Icons.straighten,
                      placed.length >= 2 && _showLines && _showDistances
                          ? Theme.of(context).colorScheme.primary
                          : (placed.length < 2 || !_showLines)
                              ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)
                              : null,
                      placed.length < 2
                          ? () => _showToastMessage('지점이 2개 이상 필요합니다')
                          : !_showLines
                              ? () => _showToastMessage('마커 연결을 먼저 켜세요')
                              : () {
                                  setState(() => _showDistances = !_showDistances);
                                  _showToastMessage(
                                      _showDistances ? '거리 표시 켜짐' : '거리 표시 꺼짐');
                                },
                    ),
                    _divider(),
                    // ── 오버레이(그래프·필터·시간) ─────────────
                    // 그래프 = 조과 마커 토글 겸용. 활성 표시는 '마커 표시' 기준이라
                    // 패널 ×로 닫아도(_showCatchChart=false) 마커가 켜져 있으면 활성 유지.
                    // 패널을 다시 보려면 버튼을 2번(끄기→켜기) 누르면 된다.
                    _toolBtn(
                      Icons.bar_chart, // 조위+시간당 조과 그래프 패널 + 조과 마커
                      (_catchBySpecies.isNotEmpty || _dayTides.isNotEmpty)
                          ? (_showCatchPoints
                              ? Theme.of(context).colorScheme.primary
                              : null)
                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                      (_catchBySpecies.isNotEmpty || _dayTides.isNotEmpty)
                          ? () {
                              final opening = !_showCatchPoints;
                              setState(() {
                                _showCatchPoints = opening; // 조과 마커
                                _showCatchChart = opening; // 그래프 패널
                                _hiddenCatchSpecies = {}; // 켤/끌 때 숨김 초기화
                              });
                              // 열 때 물때가 없으면 자동 수집해 곡선을 채운다.
                              if (opening) _ensureDayTides();
                            }
                          : () => _showToastMessage('조과·물때 정보가 없습니다'),
                    ),
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
      height: 36, // 버튼 세로 간격 10% 축소(40→36)
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

  /// 조과 차트 패널. 제목줄을 드래그해 이동, ×로 닫기. 위치는 화면 안으로 클램프.
  Widget _buildChartPanel(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ts = _stackSize(context);
    final panelW = math.min(ts.width - 16, 520.0);
    final defLeft = (ts.width - panelW) / 2;
    final left = (_chartLeft ?? defLeft).clamp(0.0, ts.width - panelW);
    // bottom=0 → 광고(스택 하단) 바로 위에 붙음. 위로 드래그하면 bottom 증가.
    final maxBottom = (ts.height - 48).clamp(0.0, double.infinity);
    final bottom = (_chartBottom ?? 0.0).clamp(0.0, maxBottom);
    return Positioned(
      left: left,
      bottom: bottom,
      width: panelW,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        color: cs.surfaceContainerHighest.withValues(alpha: 0.96),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 드래그 핸들 겸 제목줄
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) => setState(() {
                  _chartLeft =
                      (left + d.delta.dx).clamp(0.0, ts.width - panelW);
                  _chartBottom = (bottom - d.delta.dy).clamp(0.0, maxBottom);
                }),
                onPanEnd: (_) => _savePanelPositions(),
                child: Row(
                  children: [
                    Icon(Icons.drag_indicator,
                        size: 16, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                    const SizedBox(width: 2),
                    Text('조위 · 시간당 조과',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => setState(() => _showCatchChart = false),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.close, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
              CatchTideChart(
                tides: _dayTides,
                catchesBySpecies: _catchBySpecies,
                onHiddenChanged: (h) =>
                    setState(() => _hiddenCatchSpecies = h),
              ),
            ],
          ),
        ),
      ),
    );
  }
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

// 시간표시용 라벨(위치 + 문구 + 화면 오프셋). 단독은 "HH:mm", 묶음은 "첫~막" 범위.
// offset: 겹쳐 펼친 마커의 부채꼴 이동량(라벨도 같이 이동해 해당 마커 위에 붙게 함).
class _TimeLabel {
  final double lat;
  final double lng;
  final String text;
  final Offset offset;
  const _TimeLabel(this.lat, this.lng, this.text, [this.offset = Offset.zero]);
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
  final bool isCatch; // 알림/카운터로 적재된 조과 기록(🎣) — 조과 보기 ON일 때만 마커 표시
  final String? species; // 조과 마커 색(어종별)용 어종명

  _GpsPoint.fromMemo(MemoEntry e)
      : timestamp = e.timestamp,
        lat = e.latitude!,
        lng = e.longitude!,
        isMemo = true,
        text = e.text,
        photoPath = e.photoPath,
        videoPath = e.videoPath,
        fishLength = e.fishLength,
        address = null,
        isCatch = e.quickCatch,
        species = e.fishSpecies;

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
  // 그날 지점들의 미디어 목록. 사진/동영상 탭 시 이 목록으로 전체화면 갤러리를 연다.
  final List<MediaGalleryItem> galleryItems;

  const _PointPopup({
    required this.point,
    required this.savePath,
    required this.onClose,
    this.galleryItems = const [],
  });

  /// 이 지점의 미디어를 갤러리 목록에서 찾아 그 인덱스로 전체화면을 연다.
  VoidCallback? _openGallery(BuildContext context) {
    final path = point.photoPath ?? point.videoPath;
    final idx = galleryItems.indexWhere((m) => m.path == path);
    if (idx < 0) return null;
    return () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MediaGalleryScreen(
            items: galleryItems,
            initialIndex: idx,
            savePath: savePath,
          ),
        ));
  }

  @override
  Widget build(BuildContext context) {
    final mediaTap = _openGallery(context);
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
                  onTap: mediaTap,
                ),
              ),
            if (point.videoPath != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: VideoPlayerWidget(
                  videoPath: point.videoPath!,
                  height: 80,
                  onTap: mediaTap,
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

