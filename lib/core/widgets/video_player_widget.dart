import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../../features/settings/presentation/settings_provider.dart';

/// 상대경로(videos/filename) 또는 절대경로를 받아 썸네일 표시 + 전체화면 재생.
class VideoPlayerWidget extends ConsumerStatefulWidget {
  final String videoPath;
  final double? height;

  const VideoPlayerWidget({
    super.key,
    required this.videoPath,
    this.height,
  });

  @override
  ConsumerState<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends ConsumerState<VideoPlayerWidget> {
  late final Future<Uint8List?> _thumbnailFuture;

  @override
  void initState() {
    super.initState();
    final absPath = _resolve(widget.videoPath,
        ref.read(settingsProvider).valueOrNull?.savePath ?? '');
    _thumbnailFuture = VideoThumbnail.thumbnailData(
      video: absPath,
      imageFormat: ImageFormat.JPEG,
      maxHeight: 300,
      quality: 75,
    );
  }

  @override
  Widget build(BuildContext context) {
    final savePath = ref.read(settingsProvider).valueOrNull?.savePath ?? '';
    final absPath = _resolve(widget.videoPath, savePath);
    final h = widget.height ?? 120.0;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _VideoFullScreenPage(videoPath: absPath),
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          FutureBuilder<Uint8List?>(
            future: _thumbnailFuture,
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data != null) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    snapshot.data!,
                    height: h,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                );
              }
              return Container(
                height: h,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: Colors.white54, strokeWidth: 2))
                    : const Icon(Icons.videocam, color: Colors.white38, size: 40),
              );
            },
          ),
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.play_arrow, color: Colors.white, size: 32),
          ),
        ],
      ),
    );
  }
}

/// videoPath가 상대경로(videos/...)면 savePath와 합쳐 절대경로로 반환.
String _resolve(String videoPath, String savePath) {
  if (videoPath.startsWith('/')) return videoPath;
  if (savePath.isNotEmpty && !savePath.startsWith('content://')) {
    return '$savePath/$videoPath';
  }
  return videoPath;
}

class _VideoFullScreenPage extends StatefulWidget {
  final String videoPath;
  const _VideoFullScreenPage({required this.videoPath});

  @override
  State<_VideoFullScreenPage> createState() => _VideoFullScreenPageState();
}

class _VideoFullScreenPageState extends State<_VideoFullScreenPage> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.videoPath));
    _controller.initialize().then((_) {
      if (mounted) {
        setState(() => _initialized = true);
        _controller.play();
      }
    });
    _controller.setLooping(true);
    _controller.addListener(_onUpdate);
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onUpdate);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (_initialized)
              Center(
                child: AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                ),
              )
            else
              const Center(child: CircularProgressIndicator(color: Colors.white)),
            Positioned(
              top: 0,
              left: 0,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            if (_initialized)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    VideoProgressIndicator(
                      _controller,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(
                        playedColor: Colors.white,
                        bufferedColor: Colors.white38,
                        backgroundColor: Colors.white12,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _controller.value.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                        color: Colors.white,
                        size: 40,
                      ),
                      onPressed: () {
                        _controller.value.isPlaying
                            ? _controller.pause()
                            : _controller.play();
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
