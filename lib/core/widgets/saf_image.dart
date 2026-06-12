import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/saf_service.dart';

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

  bool get _needsSaf =>
      !SafImage.isAbsolute(widget.photoPath) &&
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
      final b = await SafService().readSafImage(widget.savePath, widget.photoPath);
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
      final resolved = SafImage.isAbsolute(widget.photoPath)
          ? widget.photoPath
          : '${widget.savePath}/${widget.photoPath}';
      final file = File(resolved);
      img = file.existsSync()
          ? Image.file(file, height: h, width: double.infinity, fit: widget.fit)
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
