import 'dart:async';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../settings/presentation/settings_provider.dart';
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
      final photoPath = (wmSettings != null && wmSettings.enabled)
          ? await applyWatermark(file.path, wmSettings)
          : file.path;

      if (!mounted) return;
      Navigator.of(context).pop<({String path, bool isVideo})>(
        (path: photoPath, isVideo: false),
      );
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
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
                  .updateWatermark(wm.copyWith(posX: x, posY: y)),
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
    if (old.wm.posX != widget.wm.posX || old.wm.posY != widget.wm.posY) {
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
    final lines = wm.lines
        .where((l) => l.visible)
        .map((l) => _lineText(l, wm))
        .where((s) => s.isNotEmpty)
        .toList();

    if (lines.isEmpty) return const SizedBox.shrink();

    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;
    final screenH = mq.size.height;

    final sensor = widget.previewSize;
    final photoAspect = math.max(sensor.width, sensor.height) /
        math.min(sensor.width, sensor.height);

    final marginX = wm.fontSize * screenW / 960.0;
    final marginY = wm.fontSize * screenH / (960.0 * photoAspect);

    final fontMax = mq.size.shortestSide * 0.09;
    final overlayFont = math.min(
      wm.fontSize * screenW / 480.0,
      wm.fontSize * screenH / (480.0 * photoAspect),
    ).clamp(8.0, fontMax);

    final boxColor = Color.fromARGB(
        (wm.boxOpacity * 255).round().clamp(0, 255), 0, 0, 0);

    final crossAlign = switch (wm.alignment) {
      WatermarkAlign.left => CrossAxisAlignment.start,
      WatermarkAlign.center => CrossAxisAlignment.center,
      WatermarkAlign.right => CrossAxisAlignment.end,
    };

    final textAlign = switch (wm.alignment) {
      WatermarkAlign.left => TextAlign.left,
      WatermarkAlign.center => TextAlign.center,
      WatermarkAlign.right => TextAlign.right,
    };

    final vp = mq.viewPadding;
    final posX = _dragX ?? wm.posX;
    final posY = _dragY ?? wm.posY;
    final draggable = widget.onMove != null;

    final box = Container(
      key: _boxKey,
      padding: EdgeInsets.symmetric(
        horizontal: overlayFont * 0.5,
        vertical: overlayFont * 0.3,
      ),
      decoration: BoxDecoration(
        color: boxColor,
        borderRadius: BorderRadius.circular(overlayFont * 0.2),
        // 드래그 가능함을 알리는 옅은 점선 느낌의 테두리
        border: draggable
            ? Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1)
            : null,
      ),
      child: Column(
        crossAxisAlignment: crossAlign,
        mainAxisSize: MainAxisSize.min,
        children: lines
            .map((text) => Text(
                  text,
                  textAlign: textAlign,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: overlayFont,
                    fontWeight: wm.bold ? FontWeight.bold : FontWeight.normal,
                    fontFamily: _fontFam(wm.fontFamily),
                    shadows: const [Shadow(blurRadius: 2)],
                    height: 1.35,
                  ),
                ))
            .toList(),
      ),
    );

    // 자유 위치: posX/posY(0~1) → Alignment. 여백(마진+세이프에어리어) 안쪽에 배치
    return Positioned.fill(
      child: Padding(
        padding: EdgeInsets.only(
          top: marginY + vp.top,
          bottom: marginY + vp.bottom,
          left: marginX + vp.left,
          right: marginX + vp.right,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availW = constraints.maxWidth;
            final availH = constraints.maxHeight;
            // AR과 동일: 잡은 지점 기준 상대 이동 (점프 없음)
            Offset? areaLocal(Offset global) {
              final rb =
                  _areaKey.currentContext?.findRenderObject() as RenderBox?;
              return rb?.globalToLocal(global);
            }

            void onStart(Offset global) {
              final local = areaLocal(global);
              if (local == null) return;
              final bs = _boxKey.currentContext?.size ?? Size.zero;
              final freeW = availW - bs.width;
              final freeH = availH - bs.height;
              final curX = (_dragX ?? wm.posX) * (freeW > 0 ? freeW : 0);
              final curY = (_dragY ?? wm.posY) * (freeH > 0 ? freeH : 0);
              _grabDX = curX - local.dx;
              _grabDY = curY - local.dy;
            }

            void onMove(Offset global) {
              final local = areaLocal(global);
              if (local == null) return;
              final bs = _boxKey.currentContext?.size ?? Size.zero;
              final freeW = availW - bs.width;
              final freeH = availH - bs.height;
              setState(() {
                _dragX = freeW > 0
                    ? ((local.dx + _grabDX) / freeW).clamp(0.0, 1.0)
                    : 0.0;
                _dragY = freeH > 0
                    ? ((local.dy + _grabDY) / freeH).clamp(0.0, 1.0)
                    : 0.0;
              });
            }

            return SizedBox(
              key: _areaKey,
              width: availW,
              height: availH,
              child: Align(
                alignment: Alignment(posX * 2 - 1, posY * 2 - 1),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: !draggable ? null : (d) => onStart(d.globalPosition),
                  onPanUpdate: !draggable ? null : (d) => onMove(d.globalPosition),
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
      };

  String _lineText(WatermarkLine line, WatermarkSettings wm) {
    switch (line.type) {
      case WatermarkLineType.date:
        return _fmtDate(_now, wm.dateFormat);
      case WatermarkLineType.time:
        return wm.timeFormat.isEmpty ? '' : _fmtTime(_now, wm.timeFormat);
      case WatermarkLineType.customText:
        return line.customText.trim();
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
    switch (fmt) {
      case 'yy/MM/dd': return '$yy/$mm/$dd';
      case 'MM/dd': return '$mm/$dd';
      case 'yyyy-MM-dd HH:mm:ss': return '$y-$mm-$dd $hh:$min:$sec';
      case 'yyyy-MM-dd HH:mm': return '$y-$mm-$dd $hh:$min';
      default: return '$y-$mm-$dd';
    }
  }

  String _fmtTime(DateTime dt, String fmt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final sec = dt.second.toString().padLeft(2, '0');
    return fmt == 'HH:mm:ss' ? '$hh:$min:$sec' : '$hh:$min';
  }
}
