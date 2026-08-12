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

  const SafImage({
    super.key,
    required this.photoPath,
    required this.savePath,
    this.height,
    this.fit = BoxFit.cover,
    this.fullScreen = false,
  });

  static bool isAbsolute(String path) =>
      path.startsWith('/') || RegExp(r'^[A-Za-z]:[/\\]').hasMatch(path);

  @override
  State<SafImage> createState() => _SafImageState();
}

class _SafImageState extends State<SafImage> {
  Uint8List? _bytes;
  bool _loading = false;

  // 절대경로 원본이 사라진 경우(예: 다른 기기로 백업 복원 — 원본 갤러리 파일 없음)
  // 백업이 photos/로 받아둔 사본을 가리키도록 폴백
  String get _effectivePath {
    final p = widget.photoPath;
    if (SafImage.isAbsolute(p) && !File(p).existsSync()) {
      return 'photos/${p.split('/').last}';
    }
    return p;
  }

  bool get _needsSaf =>
      !SafImage.isAbsolute(_effectivePath) &&
      SafService.isSafUri(widget.savePath);

  @override
  void initState() {
    super.initState();
    if (_needsSaf) _loadBytes();
  }

  @override
  void didUpdateWidget(SafImage old) {
    super.didUpdateWidget(old);
    if (old.photoPath != widget.photoPath || old.savePath != widget.savePath) {
      if (_needsSaf) {
        setState(() { _bytes = null; });
        _loadBytes();
      }
    }
  }

  Future<void> _loadBytes() async {
    setState(() => _loading = true);
    try {
      final b = await SafService().readSafImage(widget.savePath, _effectivePath);
      if (mounted) setState(() { _bytes = b; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;

    Widget img;
    if (_needsSaf) {
      if (_loading) {
        img = SizedBox(height: h ?? 120, child: const Center(child: CircularProgressIndicator(strokeWidth: 2)));
      } else if (_bytes != null) {
        img = Image.memory(_bytes!, height: h, width: double.infinity, fit: widget.fit);
      } else {
        img = _broken(h);
      }
    } else {
      // 로컬 경로: 절대 경로거나 로컬 savePath 기반 상대 경로
      final resolved = SafImage.isAbsolute(_effectivePath)
          ? _effectivePath
          : '${widget.savePath}/$_effectivePath';
      final file = File(resolved);
      img = file.existsSync()
          ? Image.file(
              file,
              height: h,
              width: double.infinity,
              fit: widget.fit,
              // 파일이 존재해도 미디어 권한이 없으면 열기에서 PathAccessException이
              // 난다. 기본 빨간 에러 박스 대신 플레이스홀더를 그리고, 원인이
              // 권한 부재면 설정 안내 팝업을 1회 띄운다.
              errorBuilder: (context, error, stack) {
                _maybePromptPhotoPermission(context);
                return _broken(h);
              },
            )
          : _broken(h);
    }

    if (widget.fullScreen) return img;

    return GestureDetector(
      onTap: () => _openFullScreen(context),
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
