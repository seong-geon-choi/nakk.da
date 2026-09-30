import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'saf_image.dart';
import 'video_player_widget.dart';

/// 갤러리 항목: 사진/동영상 경로와 종류.
class MediaGalleryItem {
  final String path;
  final bool isVideo;
  const MediaGalleryItem({required this.path, required this.isVideo});
}

/// 전체화면 미디어 갤러리. 좌우 스와이프로 이전/다음(사진·동영상), 상단에 위치 표시.
/// 사진은 확대 가능(확대 상태에서만 팬, 기본 배율에선 스와이프로 페이지 전환).
class MediaGalleryScreen extends StatefulWidget {
  final List<MediaGalleryItem> items;
  final int initialIndex;
  final String savePath;

  const MediaGalleryScreen({
    super.key,
    required this.items,
    required this.initialIndex,
    required this.savePath,
  });

  @override
  State<MediaGalleryScreen> createState() => _MediaGalleryScreenState();
}

class _MediaGalleryScreenState extends State<MediaGalleryScreen> {
  late final PageController _pageController;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          '${_index + 1} / ${widget.items.length}',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
        centerTitle: true,
      ),
      extendBodyBehindAppBar: true,
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.items.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) {
          final item = widget.items[i];
          if (item.isVideo) {
            return _GalleryVideoPage(
              videoPath: resolveVideoPath(item.path, widget.savePath),
              active: i == _index,
            );
          }
          return _GalleryPhotoPage(
            photoPath: item.path,
            savePath: widget.savePath,
          );
        },
      ),
    );
  }
}

/// 사진 페이지: 확대 가능. 확대 상태(배율>1)에서만 팬을 켜서, 기본 배율에서는
/// 부모 PageView가 좌우 스와이프(이전/다음)를 받도록 한다.
class _GalleryPhotoPage extends StatefulWidget {
  final String photoPath;
  final String savePath;
  const _GalleryPhotoPage({required this.photoPath, required this.savePath});

  @override
  State<_GalleryPhotoPage> createState() => _GalleryPhotoPageState();
}

class _GalleryPhotoPageState extends State<_GalleryPhotoPage> {
  final _tc = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _tc.addListener(_onTransform);
  }

  void _onTransform() {
    final z = _tc.value.getMaxScaleOnAxis() > 1.01;
    if (z != _zoomed) setState(() => _zoomed = z);
  }

  @override
  void dispose() {
    _tc.removeListener(_onTransform);
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _tc,
      panEnabled: _zoomed,
      minScale: 1,
      maxScale: 5,
      child: Center(
        child: SafImage(
          photoPath: widget.photoPath,
          savePath: widget.savePath,
          fit: BoxFit.contain,
          fullScreen: true,
        ),
      ),
    );
  }
}

/// 동영상 페이지: 현재 페이지일 때만 자동 재생, 벗어나면 정지. 탭으로 재생/일시정지.
class _GalleryVideoPage extends StatefulWidget {
  final String videoPath; // 절대 경로 또는 content:// (이미 resolve된 값)
  final bool active;
  const _GalleryVideoPage({required this.videoPath, required this.active});

  @override
  State<_GalleryVideoPage> createState() => _GalleryVideoPageState();
}

class _GalleryVideoPageState extends State<_GalleryVideoPage> {
  VideoPlayerController? _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    final c = widget.videoPath.startsWith('content://')
        ? VideoPlayerController.contentUri(Uri.parse(widget.videoPath))
        : VideoPlayerController.file(File(widget.videoPath));
    _controller = c;
    c.setLooping(true);
    c.initialize().then((_) {
      if (!mounted) return;
      setState(() => _initialized = true);
      if (widget.active) c.play();
    });
    c.addListener(_onUpdate);
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant _GalleryVideoPage old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active && _initialized) {
      widget.active ? _controller?.play() : _controller?.pause();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onUpdate);
    _controller?.dispose();
    super.dispose();
  }

  void _toggle() {
    final c = _controller;
    if (c == null || !_initialized) return;
    setState(() => c.value.isPlaying ? c.pause() : c.play());
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return GestureDetector(
      onTap: _toggle,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_initialized && c != null)
            Center(
              child: AspectRatio(
                aspectRatio: c.value.aspectRatio,
                child: VideoPlayer(c),
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          // 일시정지 상태에서만 재생 아이콘 표시
          if (_initialized && c != null && !c.value.isPlaying)
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow, color: Colors.white, size: 36),
            ),
          if (_initialized && c != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                top: false,
                child: VideoProgressIndicator(
                  c,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Colors.white,
                    bufferedColor: Colors.white38,
                    backgroundColor: Colors.white12,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
