import 'dart:io';
import 'package:flutter/material.dart';
import '../../features/memo/domain/models/memo_entry.dart';

class MemoEntryCard extends StatelessWidget {
  final MemoEntry entry;
  final int? maxLines;

  const MemoEntryCard({super.key, required this.entry, this.maxLines});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(entry: entry),
          const SizedBox(height: 6),
          if (entry.isPhoto) _PhotoBody(path: entry.photoPath!) else _TextBody(entry: entry, maxLines: maxLines),
          if (entry.fishLength != null) ...[
            const SizedBox(height: 4),
            Text(
              '📏 ${entry.fishLength!.toStringAsFixed(1)} cm',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final MemoEntry entry;
  const _Header({required this.entry});

  @override
  Widget build(BuildContext context) {
    final gpsText = entry.hasGps
        ? ' | 🛰 ${entry.latitude!.toStringAsFixed(4)}, ${entry.longitude!.toStringAsFixed(4)}'
        : '';
    return Text(
      '${entry.timeLabel}$gpsText',
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
    );
  }
}

class _TextBody extends StatelessWidget {
  final MemoEntry entry;
  final int? maxLines;
  const _TextBody({required this.entry, this.maxLines});

  @override
  Widget build(BuildContext context) {
    return Text(
      entry.text ?? '',
      style: const TextStyle(fontSize: 15, height: 1.4),
      maxLines: maxLines,
      overflow: maxLines != null ? TextOverflow.ellipsis : null,
    );
  }
}

class _PhotoBody extends StatelessWidget {
  final String path;
  const _PhotoBody({required this.path});

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    return GestureDetector(
      onTap: () => _openViewer(context, path),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: file.existsSync()
            ? Image.file(file,
                height: 120,
                width: double.infinity,
                fit: BoxFit.cover)
            : Container(
                height: 120,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Center(child: Icon(Icons.broken_image, size: 36)),
              ),
      ),
    );
  }

  void _openViewer(BuildContext context, String path) {
    // android_intent_plus 없이 flutter 기본 방식으로 전체화면 표시
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreenImagePage(path: path),
      ),
    );
  }
}

class _FullScreenImagePage extends StatelessWidget {
  final String path;
  const _FullScreenImagePage({required this.path});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
    );
  }
}
