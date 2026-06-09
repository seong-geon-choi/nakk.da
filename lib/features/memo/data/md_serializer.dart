import '../domain/models/memo_entry.dart';
import '../../location/domain/models/location_status.dart';
import '../../../core/services/tracking_service.dart';

class MdSerializer {
  // ── 쓰기 ──────────────────────────────────────────────

  static String serializeEntry(MemoEntry entry) {
    final header = entry.hasGps
        ? '### ${entry.timeLabel} | 🛰 ${_fmt(entry.latitude!)}, ${_fmt(entry.longitude!)}'
        : '### ${entry.timeLabel}';
    final parts = <String>[];
    if (entry.photoPath != null) parts.add('![](${entry.photoPath})');
    if (entry.videoPath != null) parts.add('[video](${entry.videoPath})');
    if (entry.fishLength != null) parts.add('- 📏 ${entry.fishLength!.toStringAsFixed(1)}cm');
    if (entry.text != null && entry.text!.isNotEmpty) parts.add(entry.text!);
    final body = parts.join('\n');
    return '\n---\n\n$header\n$body\n';
  }

  static String serializeLocationBlock(LocationStatus loc) {
    final timeLabel = loc.isMove
        ? '## 현황 (${_time(loc.timestamp)} 장소)'
        : '## 현황';
    final address = loc.address ??
        (loc.hasGps
            ? '${_fmt(loc.latitude!)}, ${_fmt(loc.longitude!)}'
            : '-');
    final temp = loc.temperature != null ? '${loc.temperature}°C' : '-°C';
    final tide = loc.tideName != null
        ? (loc.tideTime != null
            ? '${loc.tideName} (${loc.tideTime})'
            : loc.tideName!)
        : '-물 (- --:--)';
    final water = loc.waterTemp != null ? '${loc.waterTemp}°C' : '-°C';
    final station = (loc.stationName != null && loc.stationDistance != null)
        ? '${loc.stationName} (${loc.stationDistance!.toStringAsFixed(1)}km)'
        : '- (-.--km)';

    return '\n$timeLabel\n'
        '- 📍 $address\n'
        '- 🌡 기온: $temp | 💧 수온 $water\n'
        '- 관측소: $station | 🌊 $tide\n';
  }

  static String fileHeader(DateTime date) {
    final y = date.year;
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '# $y-$m-$d\n';
  }

  // ── 읽기 ──────────────────────────────────────────────

  static List<dynamic> parseBlocks(String content, DateTime date) {
    final result = <dynamic>[];
    // 현황 블록 먼저 파싱 (--- 구분자와 무관하게 ## 현황으로 시작)
    // 전체를 줄 단위로 처리
    final lines = content.split('\n');
    int i = 0;
    while (i < lines.length) {
      final line = lines[i].trim();

      // 현황 블록
      if (line == '## 현황' || line.startsWith('## 현황 (')) {
        final isMove = line.startsWith('## 현황 (');
        DateTime timestamp = DateTime.now();
        if (isMove) {
          final timeMatch = RegExp(r'\((\d{2}:\d{2})').firstMatch(line);
          if (timeMatch != null) {
            final parts = timeMatch.group(1)!.split(':');
            timestamp = DateTime(date.year, date.month, date.day,
                int.parse(parts[0]), int.parse(parts[1]));
          }
        }
        double? lat, lng;
        String? address;
        double? temperature;
        String? tideName, tideTime;
        double? waterTemp;
        String? stationName;
        double? stationDistance;
        i++;
        while (i < lines.length &&
            !lines[i].trim().startsWith('---') &&
            !lines[i].trim().startsWith('## ') &&
            !lines[i].trim().startsWith('# ')) {
          final l = lines[i].trim();
          if (l.startsWith('- 📍 ')) {
            final raw = l.substring('- 📍 '.length);
            final gpsMatch = RegExp(r'^(-?\d+\.\d+),\s*(-?\d+\.\d+)$').firstMatch(raw);
            if (gpsMatch != null) {
              lat = double.tryParse(gpsMatch.group(1)!);
              lng = double.tryParse(gpsMatch.group(2)!);
            } else {
              address = raw;
            }
          } else if (l.startsWith('- 🌡 ')) {
            final parts = l.substring('- 🌡 '.length).split(' | ');
            if (parts.isNotEmpty) {
              final m = RegExp(r'기온: (-?\d+\.?\d*)°C').firstMatch(parts[0]);
              if (m != null) temperature = double.tryParse(m.group(1)!);
            }
            // 구 포맷: 기온 | 🌊 물때 | 💧 수온  /  신 포맷: 기온 | 💧 수온
            if (parts.length > 1 && parts[1].trim().startsWith('🌊')) {
              // 구 포맷 — 물때가 두 번째 파트
              final tideStr = parts[1].trim().replaceFirst('🌊 ', '');
              final m = RegExp(r'^(.+?)\s*\((.+?)\)$').firstMatch(tideStr);
              if (m != null && m.group(1)!.trim() != '-물') {
                tideName = m.group(1)!.trim();
                tideTime = m.group(2)!.trim();
              } else if (!tideStr.startsWith('-')) {
                tideName = tideStr;
              }
              if (parts.length > 2) {
                final m = RegExp(r'수온 (-?\d+\.?\d*)°C').firstMatch(parts[2]);
                if (m != null) waterTemp = double.tryParse(m.group(1)!);
              }
            } else if (parts.length > 1) {
              // 신 포맷 — 두 번째 파트가 수온
              final m = RegExp(r'수온 (-?\d+\.?\d*)°C').firstMatch(parts[1]);
              if (m != null) waterTemp = double.tryParse(m.group(1)!);
            }
          } else if (l.startsWith('- 관측소: ')) {
            // 신 포맷: "- 관측소: 인천 (50.3km) | 🌊 5물 (만조 18:03)"
            // 구 포맷: "- 관측소: 인천 (50.3km)"
            final raw = l.substring('- 관측소: '.length).trim();
            final stationParts = raw.split(' | ');
            final stationRaw = stationParts[0].trim();
            final m = RegExp(r'^(.+?)\s*\((-?[\d.]+)km\)$').firstMatch(stationRaw);
            if (m != null && m.group(1)!.trim() != '-') {
              stationName = m.group(1)!.trim();
              stationDistance = double.tryParse(m.group(2)!);
            }
            if (stationParts.length > 1) {
              // 신 포맷 물때 파싱
              final tideStr = stationParts[1].trim().replaceFirst('🌊 ', '');
              final tm = RegExp(r'^(.+?)\s*\((.+?)\)$').firstMatch(tideStr);
              if (tm != null && tm.group(1)!.trim() != '-물') {
                tideName = tm.group(1)!.trim();
                tideTime = tm.group(2)!.trim();
              } else if (!tideStr.startsWith('-')) {
                tideName = tideStr;
              }
            }
          }
          i++;
        }
        result.add(LocationStatus(
          timestamp: timestamp,
          latitude: lat,
          longitude: lng,
          address: address,
          temperature: temperature,
          tideName: tideName,
          tideTime: tideTime,
          waterTemp: waterTemp,
          stationName: stationName,
          stationDistance: stationDistance,
          isMove: isMove,
        ));
        continue;
      }

      // 메모 엔트리 헤더: ### HH:mm | 🛰 lat, lng  또는  ### HH:mm
      final entryMatch = RegExp(
              r'^### (\d{2}):(\d{2})(?:\s*\|\s*🛰\s*(-?\d+\.\d+),\s*(-?\d+\.\d+))?$')
          .firstMatch(line);
      if (entryMatch != null) {
        final hour = int.parse(entryMatch.group(1)!);
        final min = int.parse(entryMatch.group(2)!);
        final lat = entryMatch.group(3) != null
            ? double.tryParse(entryMatch.group(3)!)
            : null;
        final lng = entryMatch.group(4) != null
            ? double.tryParse(entryMatch.group(4)!)
            : null;
        final ts = DateTime(date.year, date.month, date.day, hour, min);

        // 본문 수집
        final bodyLines = <String>[];
        double? fishLength;
        i++;
        while (i < lines.length &&
            !lines[i].trim().startsWith('---') &&
            !lines[i].trim().startsWith('## ') &&
            !lines[i].trim().startsWith('### ')) {
          final l = lines[i].trim();
          if (l.isNotEmpty) {
            final lm = RegExp(r'^- 📏 (\d+\.?\d*)cm$').firstMatch(l);
            if (lm != null) {
              fishLength = double.tryParse(lm.group(1)!);
            } else {
              bodyLines.add(l);
            }
          }
          i++;
        }

        final body = bodyLines.join('\n');
        final photoMatch = RegExp(r'!\[\]\((.+?)\)').firstMatch(body);
        final photoPath = photoMatch?.group(1);
        final videoMatch = RegExp(r'\[video\]\((.+?)\)').firstMatch(body);
        final videoPath = videoMatch?.group(1);
        var remaining = body;
        if (photoPath != null) remaining = remaining.replaceFirst('![]($photoPath)', '');
        if (videoPath != null) remaining = remaining.replaceFirst('[video]($videoPath)', '');
        remaining = remaining.trim();
        final text = remaining.isEmpty ? null : remaining;
        result.add(MemoEntry(
          timestamp: ts,
          latitude: lat,
          longitude: lng,
          text: text,
          photoPath: photoPath,
          videoPath: videoPath,
          fishLength: fishLength,
        ));
        continue;
      }

      i++;
    }
    result.sort((a, b) {
      final ta = a is MemoEntry ? a.timestamp : (a as LocationStatus).timestamp;
      final tb = b is MemoEntry ? b.timestamp : (b as LocationStatus).timestamp;
      return ta.compareTo(tb);
    });
    return result;
  }

  // ── 전체 재빌드 ────────────────────────────────────────

  static String buildFullContent(DateTime date, List<dynamic> blocks) {
    final sb = StringBuffer(fileHeader(date));
    for (final block in blocks) {
      if (block is LocationStatus) {
        sb.write(serializeLocationBlock(block));
      } else if (block is MemoEntry) {
        sb.write(serializeEntry(block));
      }
    }
    return sb.toString();
  }

  // ── 블록 삭제 ──────────────────────────────────────────
  // blocks are indexed in the same order as parseBlocks().

  static String removeBlockAt(String content, int index) {
    final lines = content.split('\n');
    final starts = <int>[];
    int i = 0;

    while (i < lines.length) {
      final line = lines[i].trim();

      if (line == '## 현황' || line.startsWith('## 현황 (')) {
        final rawStart = (i > 0 && lines[i - 1].trim().isEmpty) ? i - 1 : i;
        starts.add(rawStart);
        i++;
        while (i < lines.length) {
          final l = lines[i].trim();
          if (l.startsWith('---') || l.startsWith('## ') || l.startsWith('# ')) break;
          i++;
        }
        continue;
      }

      if (RegExp(r'^### \d{2}:\d{2}').hasMatch(line)) {
        int rawStart = i;
        if (i >= 1 && lines[i - 1].trim().isEmpty &&
            i >= 2 && lines[i - 2].trim() == '---') {
          rawStart = i - 2;
          if (rawStart > 0 && lines[rawStart - 1].trim().isEmpty) rawStart--;
        }
        starts.add(rawStart);
        i++;
        while (i < lines.length) {
          final l = lines[i].trim();
          if (l.startsWith('---') || l.startsWith('## ') || l.startsWith('### ')) break;
          i++;
        }
        continue;
      }

      i++;
    }

    if (index < 0 || index >= starts.length) return content;

    final start = starts[index];
    final end = index + 1 < starts.length ? starts[index + 1] : lines.length;
    final result = [...lines.sublist(0, start), ...lines.sublist(end)];
    return result.join('\n');
  }

  // ── 트래킹 포인트 파싱/쓰기 ──────────────────────────────

  static final _trackRe = RegExp(
      r'^\[//\]: # \(track:(-?\d+\.\d+),(-?\d+\.\d+),(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\)$');

  static List<TrackPoint> parseTrackPoints(String content) {
    final points = <TrackPoint>[];
    for (final line in content.split('\n')) {
      final m = _trackRe.firstMatch(line.trim());
      if (m == null) continue;
      final lat = double.tryParse(m.group(1)!);
      final lng = double.tryParse(m.group(2)!);
      final dt = DateTime.tryParse(m.group(3)!);
      if (lat != null && lng != null && dt != null) {
        points.add(TrackPoint(lat: lat, lng: lng, timestamp: dt));
      }
    }
    return points;
  }

  static String trackCommentsFor(List<TrackPoint> points) {
    if (points.isEmpty) return '';
    return points
            .map((p) =>
                '[//]: # (track:${_fmt(p.lat)},${_fmt(p.lng)},${_fmtDt(p.timestamp)})')
            .join('\n') +
        '\n';
  }

  static String _fmtDt(DateTime dt) {
    final mo = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '${dt.year}-$mo-$d $h:$mi:$s';
  }

  // ── 헬퍼 ──────────────────────────────────────────────

  static bool hasGps(LocationStatus loc) =>
      loc.latitude != null && loc.longitude != null;

  static String _fmt(double v) => v.toStringAsFixed(4);
  static String _time(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

extension on LocationStatus {
  bool get hasGps => latitude != null && longitude != null;
}
