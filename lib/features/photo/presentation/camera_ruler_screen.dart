import 'dart:async';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../settings/domain/models/app_settings.dart';
import '../../../core/utils/watermark.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
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
        ResolutionPreset.high,
        enableAudio: false,
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

  Future<void> _capture() async {
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    try {
      final file = await ctrl.takePicture();
      if (!mounted) return;

      // 워터마크 적용 (설정에서 활성화된 경우)
      final wmSettings = ref.read(settingsProvider).valueOrNull?.watermark;
      final photoPath = (wmSettings != null && wmSettings.enabled)
          ? await applyWatermark(file.path, wmSettings)
          : file.path;

      if (!mounted) return;
      Navigator.of(context).pop<String>(photoPath);
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
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
        body: Center(
            child: CircularProgressIndicator(color: Colors.white)),
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
            child: CameraPreview(ctrl),
          ),
          // 워터마크 프리뷰 오버레이
          if (wmEnabled && wm != null)
            _WatermarkOverlay(wm: wm, previewSize: ctrl.value.previewSize!),
          // 상단 바 (뒤로가기만)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
          // 워터마크 토글 — AR 카메라와 동일한 우측 중앙 아이콘 버튼
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: SafeArea(
              left: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: wm == null
                        ? null
                        : () {
                            final next = !wmEnabled;
                            ref.read(settingsProvider.notifier).updateWatermark(
                                wm.copyWith(enabled: next));
                            _showToast(
                                next ? '워터마크 표시 ON' : '워터마크 표시 OFF');
                          },
                    child: Container(
                      width: 48,
                      height: 48,
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: Color(0x99000000),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.water,
                        color: wmEnabled
                            ? const Color(0xFF40C4FF)
                            : Colors.white54,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 촬영 버튼 — 하단 SafeArea 처리
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Center(
                  child: GestureDetector(
                    onTap: _capturing ? null : _capture,
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _capturing
                            ? Colors.white.withValues(alpha: 0.5)
                            : Colors.white,
                        border: Border.all(
                            color: Colors.grey.shade400, width: 4),
                      ),
                      child: _capturing
                          ? const Padding(
                              padding: EdgeInsets.all(18),
                              child: CircularProgressIndicator(strokeWidth: 3),
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 옵션 변경 알림 토스트
          if (_toastMsg != null)
            Positioned(
              left: 24,
              right: 24,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 120),
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _toastVisible ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Text(
                            _toastMsg!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
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
  final Size previewSize; // 카메라 센서 치수 (보통 가로 방향)
  const _WatermarkOverlay({required this.wm, required this.previewSize});

  @override
  State<_WatermarkOverlay> createState() => _WatermarkOverlayState();
}

class _WatermarkOverlayState extends State<_WatermarkOverlay> {
  late DateTime _now;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
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

    // 센서 치수(보통 가로)에서 세로 사진 종횡비 계산
    // 세로 사진: 짧은 쪽 = 가로, 긴 쪽 = 세로
    final sensor = widget.previewSize;
    final photoAspect = math.max(sensor.width, sensor.height) /
        math.min(sensor.width, sensor.height);

    // applyWatermark 공식: margin = fontSize × shortSide / 960
    // Stack(StackFit.expand) → CameraPreview가 화면을 stretch하여 채움
    // → 사진 좌표 → 화면 좌표: marginX = fontSize × screenW / 960
    //                            marginY = fontSize × screenH / (960 × photoAspect)
    final marginX = wm.fontSize * screenW / 960.0;
    final marginY = wm.fontSize * screenH / (960.0 * photoAspect);

    // 폰트: 사진 픽셀의 scaledFont를 화면 좌표로 변환한 크기
    final _fontMax = mq.size.shortestSide * 0.09;
    final overlayFont = math.min(
      wm.fontSize * screenW / 480.0,
      wm.fontSize * screenH / (480.0 * photoAspect),
    ).clamp(8.0, _fontMax);

    final isTop = wm.position == WatermarkPosition.topLeft ||
        wm.position == WatermarkPosition.topRight;
    final isLeft = wm.position == WatermarkPosition.topLeft ||
        wm.position == WatermarkPosition.bottomLeft;

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
    return Positioned(
      top: isTop ? marginY + vp.top : null,
      bottom: !isTop ? marginY + vp.bottom : null,
      left: isLeft ? marginX + vp.left : null,
      right: !isLeft ? marginX + vp.right : null,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: overlayFont * 0.5,
          vertical: overlayFont * 0.3,
        ),
        decoration: BoxDecoration(
          color: boxColor,
          borderRadius: BorderRadius.circular(overlayFont * 0.2),
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
                      fontWeight:
                          wm.bold ? FontWeight.bold : FontWeight.normal,
                      fontFamily: _fontFam(wm.fontFamily),
                      shadows: const [Shadow(blurRadius: 2)],
                      height: 1.35,
                    ),
                  ))
              .toList(),
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
    switch (fmt) {
      case 'yy/MM/dd': return '$yy/$mm/$dd';
      case 'MM/dd': return '$mm/$dd';
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
