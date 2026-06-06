import 'dart:io';
import 'package:flutter/material.dart';
import '../../../features/memo/data/md_serializer.dart';
import '../../../features/memo/domain/models/memo_entry.dart';
import '../../../features/location/domain/models/location_status.dart';
import '../../../core/widgets/location_status_card.dart';
import '../../../core/widgets/saf_image.dart';
import '../../../core/services/saf_service.dart';

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

  /// SAF: filePath = "$folderUri/$filename" → folderUri 추출
  String get _folderPath {
    final p = widget.filePath;
    if (SafService.isSafUri(p)) {
      return p.substring(0, p.lastIndexOf('/'));
    }
    return File(p).parent.path;
  }

  @override
  void initState() {
    super.initState();
    _blocksFuture = _loadBlocks();
  }

  Future<List<dynamic>> _loadBlocks() async {
    String? content;
    if (SafService.isSafUri(widget.filePath)) {
      final folderUri = _folderPath;
      final filename = widget.filePath.split('/').last;
      content = await SafService().readFile(folderUri, filename);
    } else {
      final file = File(widget.filePath);
      if (!await file.exists()) return [];
      content = await file.readAsString();
    }
    if (content == null) return [];
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
                  return _ViewerMemoEntry(entry: block, savePath: _folderPath);
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

class _ViewerMemoEntry extends StatelessWidget {
  final MemoEntry entry;
  final String savePath;

  const _ViewerMemoEntry({required this.entry, required this.savePath});

  @override
  Widget build(BuildContext context) {
    final h = (MediaQuery.of(context).size.shortestSide * 0.45).clamp(180.0, 360.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EntryHeader(entry: entry),
        const SizedBox(height: 6),
        if (entry.isPhoto)
          SafImage(
            photoPath: entry.photoPath!,
            savePath: savePath,
            height: h,
          )
        else
          Text(entry.text ?? '', style: const TextStyle(fontSize: 15, height: 1.4)),
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
