import 'dart:async';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../location/presentation/location_provider.dart';
import '../../../core/utils/watermark.dart';
import '../../../core/utils/media_scanner.dart';

class CameraRulerScreen extends ConsumerStatefulWidget {
  const CameraRulerScreen({super.key});

  @override
  ConsumerState<CameraRulerScreen> createState() => _CameraRulerScreenState();
}

class _CameraRulerScreenState extends ConsumerState<CameraRulerScreen>
    with WidgetsBindingObserver {
  CameraController? _ctrl;
  String? _error;
  bool _capturing = false;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _currentZoom = 1.0;
  double _baseZoom = 1.0;
  String? _toastMsg;
  bool _toastVisible = false;
  Timer? _toastTimer;

  // 동영상 모드
  bool _isVideoMode = false;
  bool _isRecording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  ResolutionPreset _videoResolution = ResolutionPreset.high; // 720p

  // 화면은 세로 고정, 기기 방향에 따라 컨트롤만 회전
  int _uiQuarterTurns = 0; // 0=세로, 1/3=가로
  StreamSubscription<AccelerometerEvent>? _accelSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 레이아웃이 화면과 같이 돌지 않도록 세로로 고정
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 200),
    ).listen(_onAccel);
    _loadPrefsAndInit();
  }

  void _onAccel(AccelerometerEvent e) {
    final ax = e.x, ay = e.y;
    // 거의 평평하면(테이블 위 등) 방향 판단 보류
    if (ax.abs() < 3 && ay.abs() < 3) return;
    int turns;
    if (ay.abs() >= ax.abs()) {
      turns = 0; // 세로(위/아래 뒤집힘은 무시)
    } else {
      turns = ax >= 0 ? 1 : 3; // 가로 좌/우
    }
    if (turns != _uiQuarterTurns && mounted) {
      setState(() => _uiQuarterTurns = turns);
    }
  }

  /// 기기 방향에 맞춰 컨트롤(아이콘/텍스트)만 제자리에서 회전
  Widget _rot(Widget child) => AnimatedRotation(
        turns: _uiQuarterTurns / 4,
        duration: const Duration(milliseconds: 250),
        child: child,
      );

  Future<void> _loadPrefsAndInit() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('video_resolution') ?? '720p';
    if (mounted) {
      setState(() {
        _videoResolution = saved == '1080p' ? ResolutionPreset.veryHigh : ResolutionPreset.high;
      });
    }
    await _initCamera();
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _recordTimer?.cancel();
    _accelSub?.cancel();
    // 화면 방향 잠금 해제 (앱 기본값 복구)
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    WidgetsBinding.instance.removeObserver(this);
    _ctrl?.dispose();
    super.dispose();
  }

  void _showToast(String text) {
    _toastTimer?.cancel();
    setState(() {
      _toastMsg = text;
      _toastVisible = true;
    });
    _toastTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() => _toastVisible = false);
      _toastTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _toastMsg = null);
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      if (_isRecording) _stopRecording();
      ctrl.dispose();
      _ctrl = null;
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _error = '카메라를 찾을 수 없습니다');
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final ctrl = CameraController(
        back,
        _isVideoMode ? _videoResolution : ResolutionPreset.high,
        enableAudio: _isVideoMode,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await ctrl.initialize();
      _minZoom = await ctrl.getMinZoomLevel();
      _maxZoom = await ctrl.getMaxZoomLevel();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      setState(() {
        _ctrl = ctrl;
        _currentZoom = _minZoom;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '카메라 오류: $e');
    }
  }

  Future<void> _switchMode(bool toVideo) async {
    if (_isRecording) return;
    final oldCtrl = _ctrl;
    setState(() {
      _isVideoMode = toVideo;
      _ctrl = null;
    });
    await oldCtrl?.dispose();
    await _initCamera();
    _showToast(toVideo ? '동영상 모드' : '사진 모드');
  }

  Future<void> _toggleResolution() async {
    if (_isRecording) return;
    final next = _videoResolution == ResolutionPreset.high
        ? ResolutionPreset.veryHigh
        : ResolutionPreset.high;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('video_resolution', next == ResolutionPreset.veryHigh ? '1080p' : '720p');
    final oldCtrl = _ctrl;
    setState(() {
      _videoResolution = next;
      _ctrl = null;
    });
    await oldCtrl?.dispose();
    await _initCamera();
    _showToast(next == ResolutionPreset.veryHigh ? '1080p' : '720p');
  }

  Future<void> _capture() async {
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    try {
      final file = await ctrl.takePicture();
      if (!mounted) return;

      final wmSettings = ref.read(settingsProvider).valueOrNull?.watermark;
      final wmAddress = await _resolveWmAddress(wmSettings);
      final photoPath = (wmSettings != null && wmSettings.enabled)
          ? await applyWatermark(file.path, wmSettings, address: wmAddress)
          : file.path;

      if (!mounted) return;
      Navigator.of(context).pop<({String path, bool isVideo})>(
        (path: photoPath, isVideo: false),
      );
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  /// 워터마크에 주소 박스가 켜져 있을 때만 역지오코딩해 주소를 반환.
  Future<String?> _resolveWmAddress(WatermarkSettings? wm) async {
    if (wm == null || !wm.enabled) return null;
    final needsAddress = wm.boxes.any(
        (b) => b.visible && b.textContent == WatermarkTextContent.address);
    if (!needsAddress) return null;
    return ref.read(locationProvider.notifier).resolveWatermarkAddress();
  }

  Future<void> _startRecording() async {
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized || _isRecording) return;
    try {
      await ctrl.startVideoRecording();
      setState(() {
        _isRecording = true;
        _recordSeconds = 0;
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordSeconds++);
      });
    } catch (e) {
      _showToast('녹화 오류: $e');
    }
  }

  Future<void> _stopRecording() async {
    final ctrl = _ctrl;
    if (ctrl == null || !_isRecording) return;
    _recordTimer?.cancel();
    _recordTimer = null;
    try {
      final file = await ctrl.stopVideoRecording();
      if (mounted) setState(() => _isRecording = false);
      if (!mounted) return;
      final savedPath = await _saveVideo(file.path);
      if (!mounted) return;
      Navigator.of(context).pop<({String path, bool isVideo})>(
        (path: savedPath ?? file.path, isVideo: true),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isRecording = false);
        _showToast('저장 오류: $e');
      }
    }
  }

  Future<String?> _saveVideo(String tempPath) async {
    return await saveToGallery(tempPath, relativePath: 'DCIM/nakkda');
  }

  String get _timerLabel {
    final m = (_recordSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_recordSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 48),
              const SizedBox(height: 16),
              Text(_error!,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('돌아가기',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    final wm = ref.watch(settingsProvider).valueOrNull?.watermark;
    final wmEnabled = wm?.enabled ?? false;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTapDown: (d) async {
              final size = context.size;
              if (size == null) return;
              final x = (d.localPosition.dx / size.width).clamp(0.0, 1.0);
              final y = (d.localPosition.dy / size.height).clamp(0.0, 1.0);
              try {
                await _ctrl?.setFocusPoint(Offset(x, y));
                await _ctrl?.setExposurePoint(Offset(x, y));
              } catch (_) {}
            },
            onScaleStart: (d) { _baseZoom = _currentZoom; },
            onScaleUpdate: (d) {
              if (d.pointerCount < 2) return;
              final newZoom = (_baseZoom * d.scale).clamp(_minZoom, _maxZoom);
              setState(() => _currentZoom = newZoom);
              _ctrl?.setZoomLevel(newZoom);
            },
            onHorizontalDragEnd: (d) {
              if (_isRecording) return;
              final v = d.primaryVelocity ?? 0;
              if (v < -300 && !_isVideoMode) {
                _switchMode(true);
              } else if (v > 300 && _isVideoMode) {
                _switchMode(false);
              }
            },
            child: CameraPreview(ctrl),
          ),
          // 워터마크 프리뷰 (사진 모드에서만) — 드래그로 위치 이동 가능
          if (!_isVideoMode && wmEnabled && wm != null)
            _WatermarkOverlay(
              wm: wm,
              previewSize: ctrl.value.previewSize!,
              quarterTurns: _uiQuarterTurns,
              onMove: (x, y) => ref
                  .read(settingsProvider.notifier)
                  .updateWatermark(wm.copyWith(containerPosX: x, containerPosY: y)),
            ),
          // 녹화 중 인디케이터
          if (_isRecording)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: _rot(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.circle, color: Colors.red, size: 10),
                        const SizedBox(width: 6),
                        Text(
                          'REC  $_timerLabel',
                          style: const TextStyle(
                            color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    )),
                  ),
                ),
              ),
            ),
          // 상단 바
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: _rot(const Icon(Icons.arrow_back, color: Colors.white)),
                    onPressed: _isRecording ? null : () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  // 동영상 모드: 해상도 버튼
                  if (_isVideoMode)
                    GestureDetector(
                      onTap: _isRecording ? null : _toggleResolution,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: _rot(Text(
                          _videoResolution == ResolutionPreset.veryHigh ? '1080p' : '720p',
                          style: TextStyle(
                            color: _isRecording ? Colors.white38 : Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        )),
                      ),
                    ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          // 우측 중앙: 워터마크 토글 (AR 카메라와 동일한 아이콘/위치)
          if (!_isVideoMode && wm != null)
            Positioned(
              top: 0,
              bottom: 0,
              right: 8,
              child: SafeArea(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () {
                      final next = !wmEnabled;
                      ref
                          .read(settingsProvider.notifier)
                          .updateWatermark(wm.copyWith(enabled: next));
                      _showToast(next ? '워터마크 ON' : '워터마크 OFF');
                    },
                    child: Container(
                      width: 48,
                      height: 48,
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: Color(0x99000000),
                        shape: BoxShape.circle,
                      ),
                      child: _rot(Icon(
                        Icons.water_drop,
                        color: wmEnabled
                            ? const Color(0xFF40C4FF)
                            : const Color(0x80FFFFFF),
                      )),
                    ),
                  ),
                ),
              ),
            ),
          // 하단: 모드 선택 + 촬영 버튼
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 모드 선택 탭
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: _isVideoMode && !_isRecording
                              ? () => _switchMode(false)
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            child: _rot(Text(
                              '사진',
                              style: TextStyle(
                                color: !_isVideoMode ? Colors.white : Colors.white38,
                                fontSize: 14,
                                fontWeight: !_isVideoMode
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            )),
                          ),
                        ),
                        GestureDetector(
                          onTap: !_isVideoMode && !_isRecording
                              ? () => _switchMode(true)
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            child: _rot(Text(
                              '동영상',
                              style: TextStyle(
                                color: _isVideoMode ? Colors.white : Colors.white38,
                                fontSize: 14,
                                fontWeight: _isVideoMode
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            )),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // 촬영 버튼
                    GestureDetector(
                      onTap: _isVideoMode
                          ? (_isRecording ? _stopRecording : _startRecording)
                          : (_capturing ? null : _capture),
                      child: Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(color: Colors.grey.shade400, width: 4),
                        ),
                        child: Center(
                          child: _isVideoMode
                              ? AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: _isRecording ? 24 : 38,
                                  height: _isRecording ? 24 : 38,
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(
                                        _isRecording ? 5 : 19),
                                  ),
                                )
                              : (_capturing
                                  ? const Padding(
                                      padding: EdgeInsets.all(18),
                                      child: CircularProgressIndicator(strokeWidth: 3),
                                    )
                                  : null),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 토스트
          if (_toastMsg != null)
            Positioned(
              left: 24,
              right: 24,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 140),
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _toastVisible ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: Center(
                        child: _rot(Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Text(
                            _toastMsg!,
                            style: const TextStyle(
                              color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                        )),
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
}

// ── 카메라 뷰 워터마크 오버레이 ───────────────────────────────

class _WatermarkOverlay extends StatefulWidget {
  final WatermarkSettings wm;
  final Size previewSize;
  final void Function(double, double)? onMove;
  final int quarterTurns; // 기기 방향에 맞춘 박스 회전
  const _WatermarkOverlay(
      {required this.wm,
      required this.previewSize,
      this.onMove,
      this.quarterTurns = 0});

  @override
  State<_WatermarkOverlay> createState() => _WatermarkOverlayState();
}

class _WatermarkOverlayState extends State<_WatermarkOverlay> {
  late DateTime _now;
  late Timer _timer;
  // 드래그 중 로컬 위치(즉시 반영). 커밋되면 didUpdateWidget에서 해제.
  double? _dragX;
  double? _dragY;
  final _areaKey = GlobalKey();
  final _boxKey = GlobalKey();
  // 잡은 지점과 박스 좌상단의 오프셋(AR과 동일한 상대 이동)
  double _grabDX = 0;
  double _grabDY = 0;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void didUpdateWidget(covariant _WatermarkOverlay old) {
    super.didUpdateWidget(old);
    if (old.wm.containerPosX != widget.wm.containerPosX ||
        old.wm.containerPosY != widget.wm.containerPosY) {
      _dragX = null;
      _dragY = null;
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wm = widget.wm;
    final now = _now;
    final visible = wm.boxes
        .where((b) => b.visible && _boxText(b, now).isNotEmpty)
        .toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;
    final screenH = mq.size.height;

    final sensor = widget.previewSize;
    final photoAspect = math.max(sensor.width, sensor.height) /
        math.min(sensor.width, sensor.height);

    // 사진 px → 화면 px 스케일 (폰트·위치 공통). bake의 shortSide/480 비례와 일치.
    final fontScale =
        math.min(screenW / 480.0, screenH / (480.0 * photoAspect));
    final shortSidePx = fontScale * 480.0;

    // 각 박스 측정
    final sizes = <Size>[];
    final positions = <Offset>[];
    final fonts = <double>[];
    double maxFont = 0;
    for (final b in visible) {
      // 클램프 없이 bake와 동일 공식: 라이브 미리보기 = 저장 사진 크기 일치
      final f = b.fontSize * fontScale;
      fonts.add(f);
      maxFont = math.max(maxFont, f);
      final tp = TextPainter(
        text: TextSpan(
          text: _boxText(b, now),
          style: TextStyle(
            fontSize: f,
            fontWeight: _fontWeight(b.weight),
            fontFamily: _fontFam(b.fontFamily),
            height: 1.25,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: _align(b.alignment),
        textScaler: TextScaler.noScaling,
      )..layout();
      // +2px: 시스템 글꼴 배율 무시(noScaling)와 함께 서브픽셀 줄바꿈 방지
      final nat = Size(tp.width + 2, tp.height);
      // 박스 90°/270° 회전 시 footprint 가로·세로가 뒤바뀜
      sizes.add(b.quarterTurns % 2 != 0 ? Size(nat.height, nat.width) : nat);
      positions.add(Offset(b.dx * shortSidePx, b.dy * shortSidePx));
    }

    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (var i = 0; i < visible.length; i++) {
      final p = positions[i], s = sizes[i];
      minX = math.min(minX, p.dx);
      minY = math.min(minY, p.dy);
      maxX = math.max(maxX, p.dx + s.width);
      maxY = math.max(maxY, p.dy + s.height);
    }

    final pad = maxFont * 0.4;
    final containerSize =
        Size((maxX - minX) + pad * 2, (maxY - minY) + pad * 2);

    final boxColor = Color(wm.bgColorArgb);
    final draggable = widget.onMove != null;

    // 컨테이너 = 배경 + 그 안에 자유 배치된 박스들. 카메라에선 컨테이너 전체만 이동.
    final box = Container(
      key: _boxKey,
      width: containerSize.width,
      height: containerSize.height,
      decoration: BoxDecoration(
        color: boxColor,
        borderRadius: BorderRadius.circular(pad * 0.5),
        border: (draggable && !wm.hideContainerBorder)
            ? Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1)
            : null,
      ),
      child: Stack(
        children: [
          for (var i = 0; i < visible.length; i++)
            Positioned(
              left: pad + (positions[i].dx - minX),
              top: pad + (positions[i].dy - minY),
              child: Builder(builder: (_) {
                final turns = visible[i].quarterTurns;
                final swapped = turns % 2 != 0;
                // footprint(sizes[i])에서 회전 전 자연 크기 복원
                final natW = swapped ? sizes[i].height : sizes[i].width;
                final natH = swapped ? sizes[i].width : sizes[i].height;
                final t = SizedBox(
                  width: natW,
                  height: natH,
                  child: Text(
                    _boxText(visible[i], now),
                    textAlign: _align(visible[i].alignment),
                    textScaler: TextScaler.noScaling,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: Color(visible[i].textColor),
                      fontSize: fonts[i],
                      fontWeight: _fontWeight(visible[i].weight),
                      fontFamily: _fontFam(visible[i].fontFamily),
                      shadows: const [Shadow(blurRadius: 2)],
                      height: 1.25,
                    ),
                  ),
                );
                return turns % 4 == 0
                    ? t
                    : RotatedBox(quarterTurns: turns, child: t);
              }),
            ),
        ],
      ),
    );

    final margin = shortSidePx * 0.01;
    final posX = _dragX ?? wm.containerPosX;
    final posY = _dragY ?? wm.containerPosY;

    // 가로 회전 시 박스의 화면 점유 footprint는 가로/세로가 뒤바뀐다.
    // 이를 반영하지 않으면 가로에서 한 축(사용자 기준 상하) 이동 범위가 크게 줄어든다.
    final landscape = widget.quarterTurns.isOdd;
    final footW = landscape ? containerSize.height : containerSize.width;
    final footH = landscape ? containerSize.width : containerSize.height;

    // 자유 위치: posX/posY(0~1). 사진 가장자리(거의 구석)까지 배치.
    // 시스템 바 안전영역(viewPadding) 미적용 → 저장 사진과 동일하게 구석까지 이동 가능.
    return Positioned.fill(
      child: Padding(
        padding: EdgeInsets.all(margin),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availW = constraints.maxWidth;
            final availH = constraints.maxHeight;
            // footprint(회전 반영) 기준 자유 이동 범위
            final freeW = (availW - footW).clamp(0.0, double.infinity);
            final freeH = (availH - footH).clamp(0.0, double.infinity);

            Offset? areaLocal(Offset global) {
              final rb =
                  _areaKey.currentContext?.findRenderObject() as RenderBox?;
              return rb?.globalToLocal(global);
            }

            // 잡은 지점 기준 상대 이동(점프 없음) — footprint 중심 기준
            void onStart(Offset global) {
              final local = areaLocal(global);
              if (local == null) return;
              final cx = footW / 2 + (_dragX ?? wm.containerPosX) * freeW;
              final cy = footH / 2 + (_dragY ?? wm.containerPosY) * freeH;
              _grabDX = cx - local.dx;
              _grabDY = cy - local.dy;
            }

            void onMove(Offset global) {
              final local = areaLocal(global);
              if (local == null) return;
              final cx = local.dx + _grabDX;
              final cy = local.dy + _grabDY;
              setState(() {
                _dragX =
                    freeW > 0 ? ((cx - footW / 2) / freeW).clamp(0.0, 1.0) : 0.0;
                _dragY =
                    freeH > 0 ? ((cy - footH / 2) / freeH).clamp(0.0, 1.0) : 0.0;
              });
            }

            // footprint 중심 → 회전 전 박스 좌상단(중심 정렬 후 회전)
            final centerX = footW / 2 + posX * freeW;
            final centerY = footH / 2 + posY * freeH;

            return SizedBox(
              key: _areaKey,
              width: availW,
              height: availH,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: centerX - containerSize.width / 2,
                    top: centerY - containerSize.height / 2,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart:
                          !draggable ? null : (d) => onStart(d.globalPosition),
                      onPanUpdate:
                          !draggable ? null : (d) => onMove(d.globalPosition),
                      onPanEnd: !draggable
                          ? null
                          : (_) {
                              if (_dragX != null && _dragY != null) {
                                widget.onMove!(_dragX!, _dragY!);
                              }
                            },
                      child: AnimatedRotation(
                        turns: widget.quarterTurns / 4,
                        duration: const Duration(milliseconds: 250),
                        child: box,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _fontFam(WatermarkFont f) => switch (f) {
        WatermarkFont.monospace => 'monospace',
        WatermarkFont.serif => 'serif',
        WatermarkFont.sansSerif => 'sans-serif',
        WatermarkFont.heavy => kWatermarkHeavyFont,
      };

  FontWeight _fontWeight(WatermarkWeight w) => switch (w) {
        WatermarkWeight.normal => FontWeight.w400,
        WatermarkWeight.bold => FontWeight.w700,
        WatermarkWeight.black => FontWeight.w900,
      };

  TextAlign _align(WatermarkAlign a) => switch (a) {
        WatermarkAlign.left => TextAlign.left,
        WatermarkAlign.center => TextAlign.center,
        WatermarkAlign.right => TextAlign.right,
      };

  String _boxText(WatermarkBox b, DateTime now) {
    switch (b.type) {
      case WatermarkLineType.date:
        return _fmtDate(now, b.dateFormat);
      case WatermarkLineType.time:
        return b.timeFormat.isEmpty ? '' : _fmtTime(now, b.timeFormat);
      case WatermarkLineType.customText:
      case WatermarkLineType.customText2:
        return b.customText.trim();
    }
  }

  String _fmtDate(DateTime dt, String fmt) {
    final y = dt.year.toString();
    final yy = (dt.year % 100).toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final sec = dt.second.toString().padLeft(2, '0');
    final mmm = _monthAbbr[dt.month - 1];
    switch (fmt) {
      case 'yy/MM/dd': return '$yy/$mm/$dd';
      case 'MM/dd': return '$mm/$dd';
      case 'MMM/dd': return '$mmm/$dd';
      case 'yyyy MMM dd': return '$y $mmm $dd';
      case 'yyyy-MM-dd HH:mm:ss': return '$y-$mm-$dd $hh:$min:$sec';
      case 'yyyy-MM-dd HH:mm': return '$y-$mm-$dd $hh:$min';
      default: return '$y-$mm-$dd';
    }
  }

  static const _monthAbbr = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];

  String _fmtTime(DateTime dt, String fmt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final sec = dt.second.toString().padLeft(2, '0');
    return fmt == 'HH:mm:ss' ? '$hh:$min:$sec' : '$hh:$min';
  }
}
