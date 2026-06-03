import 'dart:io';
import 'package:flutter/material.dart';
import '../../../features/memo/data/md_serializer.dart';
import '../../../features/memo/domain/models/memo_entry.dart';
import '../../../features/location/domain/models/location_status.dart';
import '../../../core/widgets/location_status_card.dart';

class FileViewerScreen extends StatefulWidget {
  final String filePath;
  final String displayName;

  const FileViewerScreen({
    super.key,
    required this.filePath,
    required this.displayName,
  });

  @override
  State<FileViewerScreen> createState() => _FileViewerScreenState();
}

class _FileViewerScreenState extends State<FileViewerScreen> {
  late Future<List<dynamic>> _blocksFuture;

  @override
  void initState() {
    super.initState();
    _blocksFuture = _loadBlocks();
  }

  Future<List<dynamic>> _loadBlocks() async {
    final file = File(widget.filePath);
    if (!await file.exists()) return [];
    final content = await file.readAsString();
    return MdSerializer.parseBlocks(content);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.displayName,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        top: false,
        child: FutureBuilder<List<dynamic>>(
        future: _blocksFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final blocks = snapshot.data ?? [];
          if (blocks.isEmpty) {
            return const Center(
              child: Text('메모가 없습니다', style: TextStyle(fontSize: 15)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: blocks.length,
            separatorBuilder: (_, _) => const Divider(height: 24),
            itemBuilder: (context, index) {
              final block = blocks[index];
              if (block is MemoEntry) {
                return _ViewerMemoEntry(
                  entry: block,
                  savePath: File(widget.filePath).parent.path,
                );
              }
              if (block is LocationStatus) {
                return LocationStatusCard(status: block);
              }
              return const SizedBox.shrink();
            },
          );
        },
        ),
      ),
    );
  }
}

/// 뷰어용 메모 엔트리 — 사진은 절대 경로로 변환해서 표시
class _ViewerMemoEntry extends StatelessWidget {
  final MemoEntry entry;
  final String savePath;

  const _ViewerMemoEntry({required this.entry, required this.savePath});

  static bool _isAbsolutePath(String path) {
    // Unix 절대 경로: /로 시작
    if (path.startsWith('/')) return true;
    // Windows 절대 경로: C:\ 또는 C:/ 형태
    if (RegExp(r'^[A-Za-z]:[/\\]').hasMatch(path)) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // photoPath가 상대 경로면 절대 경로로 변환
    final resolvedEntry = entry.photoPath != null && !_isAbsolutePath(entry.photoPath!)
        ? MemoEntry(
            timestamp: entry.timestamp,
            latitude: entry.latitude,
            longitude: entry.longitude,
            text: entry.text,
            photoPath: '$savePath/${entry.photoPath}',
          )
        : entry;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 헤더: HH:mm | 🛰 lat, lng
        _EntryHeader(entry: resolvedEntry),
        const SizedBox(height: 6),
        if (resolvedEntry.isPhoto)
          _InlineImage(path: resolvedEntry.photoPath!, maxHeight: 240)
        else
          Text(
            resolvedEntry.text ?? '',
            style: const TextStyle(fontSize: 15, height: 1.4),
          ),
      ],
    );
  }
}

class _EntryHeader extends StatelessWidget {
  final MemoEntry entry;
  const _EntryHeader({required this.entry});

  @override
  Widget build(BuildContext context) {
    final gps = entry.hasGps
        ? ' | 🛰 ${entry.latitude!.toStringAsFixed(4)}, ${entry.longitude!.toStringAsFixed(4)}'
        : '';
    return Text(
      '${entry.timeLabel}$gps',
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
    );
  }
}

class _InlineImage extends StatelessWidget {
  final String path;
  final double maxHeight;

  const _InlineImage({required this.path, this.maxHeight = 240});

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    return GestureDetector(
      onTap: () => _openFullScreen(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: file.existsSync()
            ? Image.file(
                file,
                height: maxHeight,
                width: double.infinity,
                fit: BoxFit.cover,
              )
            : Container(
                height: maxHeight,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Center(
                  child: Icon(Icons.broken_image, size: 48),
                ),
              ),
      ),
    );
  }

  void _openFullScreen(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: InteractiveViewer(
              child: Image.file(
                File(path),
                fit: BoxFit.contain,
                errorBuilder: (ctx, err, stack) => const Icon(
                  Icons.broken_image,
                  color: Colors.white,
                  size: 64,
                ),
              ),
            ),
          ),
        ),
      ),
    ));
  }
}
