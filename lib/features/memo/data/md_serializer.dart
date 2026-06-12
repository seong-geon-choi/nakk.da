import '../domain/models/memo_entry.dart';
import '../../location/domain/models/location_status.dart';
import '../../weather/data/weather_service.dart';
import '../../../core/services/tracking_service.dart';

class MdSerializer {
  // ── 쓰기 ──────────────────────────────────────────────

  static String serializeEntry(MemoEntry entry) {
    final header = entry.hasGps
        ? '### ${_fmtDt(entry.timestamp)} | 🛰 ${_fmt(entry.latitude!)}, ${_fmt(entry.longitude!)}'
        : '### ${_fmtDt(entry.timestamp)}';
    final parts = <String>[];
    if (entry.photoPath != null) parts.add('![](${entry.photoPath})');
    if (entry.videoPath != null) parts.add('[video](${entry.videoPath})');
    if (entry.fishLength != null) parts.add('- 📏 ${entry.fishLength!.toStringAsFixed(1)}cm');
    final species = entry.fishSpecies?.trim();
    if (species != null && species.isNotEmpty) parts.add('- 🐟 $species');
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

    final windPart = (loc.windSpeed != null && loc.windDeg != null)
        ? '🌬 ${windDegToDirection(loc.windDeg!)} ${loc.windSpeed!.toStringAsFixed(1)}m/s'
        : null;
    final weatherPart =
        loc.weatherCode != null ? '⛅ ${weatherCodeToDesc(loc.weatherCode!)}' : null;
    final weatherLine = [windPart, weatherPart].whereType<String>().join(' | ');

    return '\n$timeLabel\n'
        '- 📍 $address\n'
        '- 🌡 기온: $temp | 💧 수온 $water\n'
        '- 관측소: $station | 🌊 $tide\n'
        '${weatherLine.isNotEmpty ? '- $weatherLine\n' : ''}';
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
        double? windSpeed;
        int? windDeg;
        int? weatherCode;
        i++;
        while (i < lines.length &&
            !lines[i].trim().startsWith('---') &&
            !lines[i].trim().startsWith('## ') &&
            !lines[i].trim().startsWith('# ') &&
            !lines[i].trim().startsWith('[//]: # (')) {
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
          } else if (l.startsWith('- 🌬 ') || (l.startsWith('- ') && l.contains('🌬'))) {
            // 바람/날씨 줄: "- 🌬 남서 3.2m/s | ⛅ 맑음"
            final raw = l.replaceFirst(RegExp(r'^- '), '');
            final parts = raw.split(' | ');
            for (final part in parts) {
              if (part.contains('🌬')) {
                final m = RegExp(r'🌬 \S+ (-?\d+\.?\d*)m/s').firstMatch(part);
                if (m != null) windSpeed = double.tryParse(m.group(1)!);
              }
              if (part.contains('⛅')) {
                // weatherCode는 저장 안 함 — 텍스트만 표시용
              }
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
          windSpeed: windSpeed,
          windDeg: windDeg,
          weatherCode: weatherCode,
        ));
        continue;
      }

      // 메모 엔트리 헤더 — 신 형식: ### YYYY-MM-DD HH:mm:ss [| 🛰 lat, lng]
      //                    구 형식: ### HH:mm [| 🛰 lat, lng]  (하위 호환)
      final newEntryMatch = RegExp(
              r'^### (\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})(?:\s*\|\s*🛰\s*(-?\d+\.\d+),\s*(-?\d+\.\d+))?$')
          .firstMatch(line);
      final oldEntryMatch = newEntryMatch == null
          ? RegExp(r'^### (\d{2}):(\d{2})(?:\s*\|\s*🛰\s*(-?\d+\.\d+),\s*(-?\d+\.\d+))?$')
              .firstMatch(line)
          : null;
      if (newEntryMatch != null || oldEntryMatch != null) {
        final DateTime ts;
        final double? lat;
        final double? lng;
        if (newEntryMatch != null) {
          ts = DateTime(
            int.parse(newEntryMatch.group(1)!),
            int.parse(newEntryMatch.group(2)!),
            int.parse(newEntryMatch.group(3)!),
            int.parse(newEntryMatch.group(4)!),
            int.parse(newEntryMatch.group(5)!),
            int.parse(newEntryMatch.group(6)!),
          );
          lat = newEntryMatch.group(7) != null ? double.tryParse(newEntryMatch.group(7)!) : null;
          lng = newEntryMatch.group(8) != null ? double.tryParse(newEntryMatch.group(8)!) : null;
        } else {
          ts = DateTime(date.year, date.month, date.day,
              int.parse(oldEntryMatch!.group(1)!), int.parse(oldEntryMatch.group(2)!));
          lat = oldEntryMatch.group(3) != null ? double.tryParse(oldEntryMatch.group(3)!) : null;
          lng = oldEntryMatch.group(4) != null ? double.tryParse(oldEntryMatch.group(4)!) : null;
        }

        // 본문 수집
        final bodyLines = <String>[];
        double? fishLength;
        String? fishSpecies;
        i++;
        while (i < lines.length &&
            !lines[i].trim().startsWith('---') &&
            !lines[i].trim().startsWith('## ') &&
            !lines[i].trim().startsWith('### ') &&
            !lines[i].trim().startsWith('[//]: # (')) {
          final l = lines[i].trim();
          if (l.isNotEmpty) {
            final lm = RegExp(r'^- 📏 (\d+\.?\d*)cm$').firstMatch(l);
            final sm = RegExp(r'^- 🐟 (.+)$').firstMatch(l);
            if (lm != null) {
              fishLength = double.tryParse(lm.group(1)!);
            } else if (sm != null) {
              var rest = sm.group(1)!.trim();
              // 구 포맷의 "N마리" 접미사 제거 (마릿수는 더 이상 저장하지 않음)
              final cm = RegExp(r'\s*\d+\s*마리$').firstMatch(rest);
              if (cm != null) rest = rest.substring(0, cm.start).trim();
              if (rest.isNotEmpty) fishSpecies = rest;
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
          fishSpecies: fishSpecies,
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

  static String buildFullContent(DateTime date, List<dynamic> blocks,
      [List<TrackPoint> trackPoints = const []]) {
    final sb = StringBuffer(fileHeader(date));
    for (final block in blocks) {
      if (block is LocationStatus) {
        sb.write(serializeLocationBlock(block));
      } else if (block is MemoEntry) {
        sb.write(serializeEntry(block));
      }
    }
    if (trackPoints.isNotEmpty) {
      sb.write(trackCommentsFor(trackPoints));
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

      if (RegExp(r'^### (?:\d{2}:\d{2}|\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})').hasMatch(line)) {
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
    final joined = points
        .map((p) =>
            '[//]: # (track:${_fmt(p.lat)},${_fmt(p.lng)},${_fmtDt(p.timestamp)})')
        .join('\n');
    return '$joined\n';
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
