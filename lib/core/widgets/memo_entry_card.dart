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
    final catchLabel = _catchLabel(entry);
    final media = _buildMedia(catchLabel);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(entry: entry),
          const SizedBox(height: 6),
          if (media != null) media,
          // 미디어가 없을 때만 조과 정보를 본문 위에 텍스트로 표시
          if (media == null && catchLabel != null)
            Text(
              catchLabel,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          if (entry.text != null && entry.text!.isNotEmpty) ...[
            const SizedBox(height: 6),
            _TextBody(entry: entry, maxLines: maxLines),
          ],
        ],
      ),
    );
  }

  /// 사진/동영상 위에 조과(어종·길이) 배지를 겹쳐 표시.
  Widget? _buildMedia(String? catchLabel) {
    Widget? child;
    if (entry.photoPath != null) {
      child = SafImage(photoPath: entry.photoPath!, savePath: savePath, height: 120);
    } else if (entry.videoPath != null) {
      child = VideoPlayerWidget(videoPath: entry.videoPath!, height: 120);
    }
    if (child == null) return null;
    if (catchLabel == null) return child;
    return Stack(
      children: [
        child,
        Positioned(left: 6, top: 6, child: _CatchBadge(label: catchLabel)),
      ],
    );
  }
}

/// 사진 위에 얹는 조과 정보 배지 (반투명 배경 + 흰 글자).
class _CatchBadge extends StatelessWidget {
  final String label;
  const _CatchBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
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
