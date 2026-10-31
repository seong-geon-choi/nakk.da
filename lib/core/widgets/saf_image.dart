import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/saf_service.dart';

/// 사진 열기 실패(권한 부재) 안내 팝업을 앱 실행당 1회만 띄우기 위한 가드.
/// 여러 사진 카드가 동시에 실패해도 팝업이 중복으로 뜨지 않게 한다.
bool _photoPermissionPromptShown = false;

/// 절대 로컬 경로(카메라) 또는 SAF 상대 경로(갤러리) 모두 처리하는 이미지 위젯
class SafImage extends StatefulWidget {
  final String photoPath;   // 절대 경로 or "photos/xxx.jpg" 상대 경로
  final String savePath;    // SAF URI 또는 로컬 폴더 경로
  final double? height;
  final BoxFit fit;
  final bool fullScreen;
  // 지정 시 사진 탭 동작을 대체(예: 갤러리 열기). null이면 기본 단일 전체화면.
  final VoidCallback? onTap;

  const SafImage({
    super.key,
    required this.photoPath,
    required this.savePath,
    this.height,
    this.fit = BoxFit.cover,
    this.fullScreen = false,
    this.onTap,
  });

  static bool isAbsolute(String path) =>
      path.startsWith('/') || RegExp(r'^[A-Za-z]:[/\\]').hasMatch(path);

  @override
  State<SafImage> createState() => _SafImageState();
}

class _SafImageState extends State<SafImage> {
  Uint8List? _bytes;      // 바이트로 그리는 경우(SAF/MediaStore/폴백)
  String? _directFile;    // File 로 직접 그리는 경우의 경로(로컬 전용)
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(SafImage old) {
    super.didUpdateWidget(old);
    if (old.photoPath != widget.photoPath || old.savePath != widget.savePath) {
      setState(() { _bytes = null; _directFile = null; });
      _resolve();
    }
  }

  void _resolve() {
    final p = widget.photoPath;
    if (SafImage.isAbsolute(p)) {
      // 절대경로(예: DCIM 워터마크 사진)는 항상 바이트로 로드한다.
      // 직접 File → (재설치 UID 변경 등으로 실패 시) MediaStore → 백업 photos/ 사본 순.
      _loadAbsolute(p);
    } else if (SafService.isSafUri(widget.savePath)) {
      _loadSaf(p);
    } else {
      // 로컬 savePath 기반 상대경로: 앱 소유 폴더라 File 직접 렌더.
      final local = '${widget.savePath}/$p';
      setState(() => _directFile = File(local).existsSync() ? local : null);
    }
  }

  Future<void> _loadSaf(String subpath) async {
    setState(() => _loading = true);
    try {
      final b = await SafService().readSafImage(widget.savePath, subpath);
      if (mounted) setState(() { _bytes = b; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAbsolute(String absPath) async {
    setState(() => _loading = true);
    Uint8List? b;
    // 1) 직접 File 읽기(같은 기기·같은 UID면 성공)
    try {
      final f = File(absPath);
      if (f.existsSync()) b = await f.readAsBytes();
    } catch (_) {}
    // 2) MediaStore(소유자와 무관하게 읽힘 — 재설치 UID 변경 폴백)
    if (b == null || b.isEmpty) {
      b = await SafService().readImageViaMediaStore(absPath);
    }
    // 3) 백업이 받아둔 SAF/로컬 photos/ 사본(다른 기기 복원 시)
    if (b == null || b.isEmpty) {
      final sub = 'photos/${absPath.split('/').last}';
      try {
        if (SafService.isSafUri(widget.savePath)) {
          b = await SafService().readSafImage(widget.savePath, sub);
        } else {
          final f = File('${widget.savePath}/$sub');
          if (f.existsSync()) b = await f.readAsBytes();
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() { _bytes = b; _loading = false; });
    // 전부 실패 + 미디어 권한 부재면 설정 안내 1회.
    if (b == null || b.isEmpty) _maybePromptPhotoPermission(context);
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;

    Widget img;
    if (_loading) {
      img = SizedBox(
          height: h ?? 120,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)));
    } else if (_directFile != null) {
      img = Image.file(
        File(_directFile!),
        height: h,
        width: double.infinity,
        fit: widget.fit,
        errorBuilder: (context, error, stack) {
          _maybePromptPhotoPermission(context);
          return _broken(h);
        },
      );
    } else if (_bytes != null) {
      img = Image.memory(_bytes!, height: h, width: double.infinity, fit: widget.fit);
    } else {
      img = _broken(h);
    }

    if (widget.fullScreen) return img;

    return GestureDetector(
      onTap: widget.onTap ?? () => _openFullScreen(context),
      child: ClipRRect(borderRadius: BorderRadius.circular(8), child: img),
    );
  }

  Widget _broken(double? h) => Container(
    height: h ?? 120,
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: const Center(child: Icon(Icons.broken_image, size: 36)),
  );

  /// 사진 열기 실패가 미디어 권한 부재 때문이면 설정으로 가이드하는 팝업을 띄운다.
  /// 권한이 이미 있으면(파일 누락 등 다른 원인) 팝업을 띄우지 않는다. 앱 실행당 1회.
  Future<void> _maybePromptPhotoPermission(BuildContext context) async {
    if (_photoPermissionPromptShown) return;
    final status = await Permission.photos.status;
    if (status.isGranted) return; // 권한 있음 → 파일 문제이므로 안내하지 않음
    _photoPermissionPromptShown = true;
    if (!context.mounted) return;
    final goSettings = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('사진 접근 권한 필요'),
        content: const Text(
          '저장된 사진을 표시하려면 사진 접근 권한이 필요합니다.\n'
          '설정에서 권한을 허용한 뒤 다시 실행해 주세요.\n\n'
          '설정 → 권한 → 사진 및 동영상 → 허용',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('설정 열기'),
          ),
        ],
      ),
    );
    if (goSettings == true) openAppSettings();
  }

  void _openFullScreen(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.transparent, foregroundColor: Colors.white),
        body: SafeArea(
          top: false,
          child: Center(
            child: InteractiveViewer(
              child: SafImage(
                photoPath: widget.photoPath,
                savePath: widget.savePath,
                fit: BoxFit.contain,
                fullScreen: true,
              ),
            ),
          ),
        ),
      ),
    ));
  }
}
