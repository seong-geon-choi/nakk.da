import 'package:flutter/material.dart';
import '../../features/memo/domain/models/memo_entry.dart';
import 'saf_image.dart';
import 'video_player_widget.dart';

class MemoEntryCard extends StatelessWidget {
  final MemoEntry entry;
  final String savePath;
  final int? maxLines;

  const MemoEntryCard({super.key, required this.entry, required this.savePath, this.maxLines});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(entry: entry),
          const SizedBox(height: 6),
          if (entry.photoPath != null)
            SafImage(photoPath: entry.photoPath!, savePath: savePath, height: 120),
          if (entry.videoPath != null)
            VideoPlayerWidget(videoPath: entry.videoPath!, height: 120),
          if (_catchLabel(entry) != null) ...[
            const SizedBox(height: 4),
            Text(
              _catchLabel(entry)!,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (entry.text != null && entry.text!.isNotEmpty) ...[
            const SizedBox(height: 6),
            _TextBody(entry: entry, maxLines: maxLines),
          ],
        ],
      ),
    );
  }
}

/// 어종·길이를 한 줄로 합쳐 표시. 모두 없으면 null.
String? _catchLabel(MemoEntry entry) {
  final parts = <String>[];
  final species = entry.fishSpecies?.trim();
  if (species != null && species.isNotEmpty) parts.add('🐟 $species');
  if (entry.fishLength != null) parts.add('📏 ${entry.fishLength!.toStringAsFixed(1)}cm');
  return parts.isEmpty ? null : parts.join('  ·  ');
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
