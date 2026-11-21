import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../services/video_tools.dart';
import '../utils/media_scanner.dart';
import 'video_player_widget.dart' show videoEdits;

/// 영상 자르기: 미리보기를 보며 시작·끝을 정해 원본을 바꾸거나(기본) 새 영상으로 저장.
/// 재인코딩 없이 자르므로 시작점은 직전 키프레임(약 1초 이내)으로 맞춰진다.
/// 원본을 바꾸면 true를 반환한다.
class VideoTrimScreen extends StatefulWidget {
  final String videoPath; // 절대 경로 또는 content://
  const VideoTrimScreen({super.key, required this.videoPath});

  @override
  State<VideoTrimScreen> createState() => _VideoTrimScreenState();
}

class _VideoTrimScreenState extends State<VideoTrimScreen> {
  static const _kThumbs = 8;
  static const _kMinMs = 1000.0;
  late final VideoPlayerController _c;
  bool _ready = false;
  double _durMs = 0;
  RangeValues _range = const RangeValues(0, 0);
  List<Uint8List?> _thumbs = const [];
  bool _saving = false;

  bool get _isContent => widget.videoPath.startsWith('content://');

  @override
  void initState() {
    super.initState();
    _c = _isContent
        ? VideoPlayerController.contentUri(Uri.parse(widget.videoPath))
        : VideoPlayerController.file(File(widget.videoPath));
    _c.addListener(_onTick);
    _c.initialize().then((_) {
      if (!mounted) return;
      final d = _c.value.duration.inMilliseconds.toDouble();
      setState(() {
        _ready = true;
        _durMs = d;
        _range = RangeValues(0, d);
      });
      _loadThumbs();
    });
  }

  /// 아래 막대용 썸네일(파일 경로일 때만 — content://는 막대 색으로 대신).
  Future<void> _loadThumbs() async {
    if (_isContent || _durMs <= 0) return;
    final list = <Uint8List?>[];
    for (var i = 0; i < _kThumbs; i++) {
      final t = (_durMs * (i + 0.5) / _kThumbs).round();
      Uint8List? b;
      try {
        b = await VideoThumbnail.thumbnailData(
            video: widget.videoPath, timeMs: t, maxHeight: 96, quality: 60);
      } catch (_) {}
      list.add(b);
      if (!mounted) return;
    }
    setState(() => _thumbs = list);
  }

  /// 재생이 끝 손잡이를 넘으면 시작으로 돌아가 구간만 반복.
  void _onTick() {
    if (!_ready) return;
    final pos = _c.value.position.inMilliseconds;
    if (_c.value.isPlaying && pos >= _range.end) {
      _c.seekTo(Duration(milliseconds: _range.start.round()));
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_onTick);
    _c.dispose();
    super.dispose();
  }

  void _onRange(RangeValues v) {
    if (v.end - v.start < _kMinMs) return;
    final movedStart = v.start != _range.start;
    _c.pause();
    _c.seekTo(Duration(milliseconds: (movedStart ? v.start : v.end).round()));
    setState(() => _range = v);
  }

  void _playRange() {
    if (_c.value.isPlaying) {
      _c.pause();
      return;
    }
    _c.seekTo(Duration(milliseconds: _range.start.round()));
    _c.play();
  }

  Future<void> _save({required bool replace}) async {
    if (replace) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: const Text('원본 영상을 자른 영상으로 바꿉니다.\n되돌릴 수 없습니다.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('취소')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('바꾸기')),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    await _c.pause();
    setState(() => _saving = true);
    try {
      final tmp = await getTemporaryDirectory();
      final out =
          '${tmp.path}/trim_${DateTime.now().millisecondsSinceEpoch}.mp4';
      await VideoTools.trim(widget.videoPath, _range.start.round(),
          _range.end.round(), out);
      if (replace) {
        await VideoTools.replace(out, widget.videoPath);
        videoEdits.value++;
        nav.pop(true);
      } else {
        final saved = await saveToGallery(out);
        if (saved != null) File(out).delete().catchError((_) => File(out));
        messenger.showSnackBar(SnackBar(
            content: Text(saved != null ? '새 영상으로 저장했습니다(DCIM/nakkda)' : '저장 실패')));
        nav.pop(false);
      }
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(
          content: Text(replace
              ? '원본을 바꿀 수 없습니다. 새 영상으로 저장해 보세요.'
              : '저장 실패: $e')));
    }
  }

  String _fmt(double ms) {
    final d = Duration(milliseconds: ms.round());
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    final t = (d.inMilliseconds % 1000) ~/ 100;
    return '$m:$s.$t';
  }

  @override
  Widget build(BuildContext context) {
    const label = TextStyle(color: Colors.white70, fontSize: 13);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('영상 자르기'),
      ),
      body: SafeArea(
        top: false,
        child: !_ready
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : Column(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _playRange,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AspectRatio(
                            aspectRatio: _c.value.aspectRatio,
                            child: VideoPlayer(_c),
                          ),
                          if (!_c.value.isPlaying)
                            Container(
                              width: 56,
                              height: 56,
                              decoration: const BoxDecoration(
                                  color: Colors.black54, shape: BoxShape.circle),
                              child: const Icon(Icons.play_arrow,
                                  color: Colors.white, size: 36),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _strip(),
                  RangeSlider(
                    values: _range,
                    min: 0,
                    max: _durMs,
                    activeColor: Colors.amber,
                    inactiveColor: Colors.white24,
                    onChanged: _saving ? null : _onRange,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('시작 ${_fmt(_range.start)}', style: label),
                        Text('길이 ${_fmt(_range.end - _range.start)}',
                            style: label.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                        Text('끝 ${_fmt(_range.end)}', style: label),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 6, 24, 0),
                    child: Text('시작점은 가장 가까운 앞 키프레임(1초 이내)으로 맞춰집니다',
                        style: TextStyle(color: Colors.white38, fontSize: 11)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: _saving
                        ? const SizedBox(
                            height: 48,
                            child: Center(
                                child: CircularProgressIndicator(
                                    color: Colors.white)))
                        : Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(0, 48)),
                                  onPressed: () => _save(replace: false),
                                  child: const Text('새 영상으로 저장'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                      minimumSize: const Size(0, 48)),
                                  onPressed: () => _save(replace: true),
                                  child: const Text('원본 바꾸기'),
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  /// 썸네일 막대 + 선택 구간 밖은 어둡게.
  Widget _strip() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        height: 48,
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          final l = _durMs > 0 ? _range.start / _durMs * w : 0.0;
          final r = _durMs > 0 ? (1 - _range.end / _durMs) * w : 0.0;
          final pos = _durMs > 0
              ? _c.value.position.inMilliseconds / _durMs * w
              : 0.0;
          return Stack(
            children: [
              Row(
                children: [
                  for (var i = 0; i < _kThumbs; i++)
                    Expanded(
                      child: i < _thumbs.length && _thumbs[i] != null
                          ? Image.memory(_thumbs[i]!,
                              fit: BoxFit.cover, height: 48, gaplessPlayback: true)
                          : Container(color: Colors.white12),
                    ),
                ],
              ),
              Positioned(
                  left: 0, top: 0, bottom: 0, width: l,
                  child: Container(color: Colors.black54)),
              Positioned(
                  right: 0, top: 0, bottom: 0, width: r,
                  child: Container(color: Colors.black54)),
              Positioned(
                  left: l, right: r, top: 0, bottom: 0,
                  child: Container(
                      decoration: BoxDecoration(
                          border: Border.all(color: Colors.amber, width: 2)))),
              Positioned(
                  left: pos.clamp(0.0, w - 2), top: 0, bottom: 0, width: 2,
                  child: Container(color: Colors.white)),
            ],
          );
        }),
      ),
    );
  }
}
