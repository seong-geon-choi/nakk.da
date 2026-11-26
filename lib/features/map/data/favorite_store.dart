import 'dart:io';

import '../../../core/services/saf_service.dart';

/// 지도 즐겨찾기 포인트(이름·메모·좌표).
class FavoritePoint {
  final String name;
  final String memo;
  final double lat, lng;
  final DateTime created;

  const FavoritePoint({
    required this.name,
    this.memo = '',
    required this.lat,
    required this.lng,
    required this.created,
  });

  FavoritePoint copyWith({String? name, String? memo, double? lat, double? lng}) =>
      FavoritePoint(
        name: name ?? this.name,
        memo: memo ?? this.memo,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        created: created,
      );

  /// 같은 포인트 판별(복원 병합용) — 좌표(소수 6자리) + 이름.
  String get key => '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)},$name';
}

/// 저장 폴더의 `즐겨찾기.md`에 즐겨찾기를 모아 둔다.
/// 형식(사람이 읽을 수 있게 + 좌표는 숨김 주석):
/// ```
/// # ⭐ 즐겨찾기
///
/// - 이름 | 메모
///   [//]: # (fav:37.0012345, 126.4567890 | 2026-11-25 14:30)
/// ```
/// 날짜 이름 파일이 아니라 날짜 목록·검색에는 나타나지 않고, 메모 백업에는 함께 올라간다.
class FavoriteStore {
  static const fileName = '즐겨찾기.md';
  final _saf = SafService();

  static final _favRe = RegExp(
      r'^\[//\]: # \(fav:(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)\s*\|\s*(\d{4}-\d{2}-\d{2}(?: \d{2}:\d{2})?)\)$');

  Future<List<FavoritePoint>> load(String savePath) async {
    if (savePath.isEmpty) return [];
    try {
      String? content;
      if (SafService.isSafUri(savePath)) {
        content = await _saf.readFile(savePath, fileName);
      } else {
        final f = File('$savePath/$fileName');
        if (await f.exists()) content = await f.readAsString();
      }
      return content == null ? [] : parse(content);
    } catch (_) {
      return [];
    }
  }

  Future<void> save(String savePath, List<FavoritePoint> points) async {
    final content = build(points);
    if (SafService.isSafUri(savePath)) {
      await _saf.writeFile(savePath, fileName, content);
    } else {
      final f = File('$savePath/$fileName');
      await f.parent.create(recursive: true);
      await f.writeAsString(content);
    }
  }

  static List<FavoritePoint> parse(String content) {
    final out = <FavoritePoint>[];
    String? visible; // 직전 '- 이름 | 메모' 줄
    for (final raw in content.split('\n')) {
      final line = raw.trim();
      if (line.startsWith('- ')) {
        visible = line.substring(2);
        continue;
      }
      final m = _favRe.firstMatch(line);
      if (m == null || visible == null) continue;
      final lat = double.tryParse(m.group(1)!);
      final lng = double.tryParse(m.group(2)!);
      final created = DateTime.tryParse(m.group(3)!);
      if (lat == null || lng == null) continue;
      final sep = visible.indexOf(' | ');
      out.add(FavoritePoint(
        name: (sep < 0 ? visible : visible.substring(0, sep)).trim(),
        memo: sep < 0 ? '' : visible.substring(sep + 3).trim(),
        lat: lat,
        lng: lng,
        created: created ?? DateTime.now(),
      ));
      visible = null;
    }
    return out;
  }

  static String build(List<FavoritePoint> points) {
    final sb = StringBuffer('# ⭐ 즐겨찾기\n\n');
    for (final p in points) {
      final date = formatCreated(p.created);
      sb.write('- ${clean(p.name)}');
      if (p.memo.trim().isNotEmpty) sb.write(' | ${clean(p.memo)}');
      sb.write('\n  [//]: # (fav:${p.lat.toStringAsFixed(7)}, '
          '${p.lng.toStringAsFixed(7)} | $date)\n');
    }
    return sb.toString();
  }

  /// 저장 일시 'yyyy-MM-dd HH:mm'(파일 기록·화면 표시 공용).
  static String formatCreated(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  /// 파일 형식을 깨지 않게 줄바꿈·구분자(|)를 바꾼다.
  static String clean(String s) =>
      s.replaceAll(RegExp(r'[\r\n]+'), ' ').replaceAll('|', '/').trim();

  /// 복원 병합: 로컬 + 드라이브의 합집합(같은 좌표·이름은 하나만, 로컬 우선).
  static String merge(String local, String remote) {
    final merged = <String, FavoritePoint>{};
    for (final p in parse(remote)) {
      merged[p.key] = p;
    }
    for (final p in parse(local)) {
      merged[p.key] = p;
    }
    return build(merged.values.toList());
  }
}
