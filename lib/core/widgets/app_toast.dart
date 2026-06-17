import 'package:flutter/material.dart';

/// 화면 상단(앱바 아래 16)에 잠깐 떴다 사라지는 토스트.
/// 지도·공유 등에서 공통으로 사용. Overlay에 삽입되므로 호출 화면이
/// 별도 상태/Stack을 관리할 필요가 없다(context만 있으면 됨).
///
/// - 기본: 반투명 검정 알약(지도 버튼 안내용).
/// - [emphasized] = true: 밝은 강조형(아이콘+그림자) — 공유 시트처럼
///   배경이 어두워진 위에서도 눈에 띄도록.
///
/// 연속 호출 시 이전 토스트는 즉시 제거되고 새 메시지로 교체된다.
typedef _ToastDismiss = void Function();

_ToastDismiss? _activeDismiss;

void showAppToast(
  BuildContext context,
  String message, {
  Duration duration = const Duration(milliseconds: 1800),
  bool emphasized = false,
}) {
  final overlay = Overlay.of(context);
  // 이전 토스트 제거(지도의 Timer-cancel 동작과 동일)
  _activeDismiss?.call();

  late OverlayEntry entry;
  var removed = false;
  late final _ToastDismiss dismiss;
  dismiss = () {
    if (removed) return;
    removed = true;
    if (_activeDismiss == dismiss) _activeDismiss = null;
    entry.remove();
  };

  entry = OverlayEntry(
    builder: (_) => _ToastOverlay(
      message: message,
      duration: duration,
      emphasized: emphasized,
      onDismissed: dismiss,
    ),
  );
  _activeDismiss = dismiss;
  overlay.insert(entry);
}

class _ToastOverlay extends StatefulWidget {
  final String message;
  final Duration duration;
  final bool emphasized;
  final VoidCallback onDismissed;
  const _ToastOverlay({
    required this.message,
    required this.duration,
    required this.emphasized,
    required this.onDismissed,
  });

  @override
  State<_ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends State<_ToastOverlay> {
  double _opacity = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _opacity = 1);
    });
    Future.delayed(widget.duration, () {
      if (mounted) setState(() => _opacity = 0);
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) widget.onDismissed();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return Positioned(
      top: topInset + kToolbarHeight + 16,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _opacity,
          duration: const Duration(milliseconds: 300),
          // Material 조상이 없으면 텍스트에 노란 밑줄(기본 디버그 스타일)이
          // 생기므로 투명 Material로 감싼다.
          child: Material(
            color: Colors.transparent,
            child: Center(
              child: widget.emphasized ? _buildEmphasized() : _buildPlain(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlain() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xCC000000),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          widget.message,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      );

  Widget _buildEmphasized() => Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E88E5),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                widget.message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      );
}
