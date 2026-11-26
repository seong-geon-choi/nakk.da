import 'dart:io';

import '../../../core/services/saf_service.dart';

/// 지도 즐겨찾기 포인트(이름·메모·좌표·카테고리).
class FavoritePoint {
  final String name;
  final String memo;
  final double lat, lng;
  final DateTime created;
  final String category;

  const FavoritePoint({
    required this.name,
    this.memo = '',
    required this.lat,
    required this.lng,
    required this.created,
    this.category = FavoriteStore.defaultCategory,
  });

  FavoritePoint copyWith({String? name, String? memo, String? category}) =>
      FavoritePoint(
        name: name ?? this.name,
        memo: memo ?? this.memo,
        lat: lat,
        lng: lng,
        created: created,
        category: category ?? this.category,
      );

  /// 같은 포인트 판별(복원 병합용) — 좌표(소수 6자리) + 이름.
  String get key => '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)},$name';
}

/// 즐겨찾기 카테고리(이름·마커 색). 파일 안의 순서가 표시 순서.
class FavoriteCategory {
  final String name;
  final int color; // ARGB

  const FavoriteCategory(this.name, this.color);

  FavoriteCategory copyWith({String? name, int? color}) =>
      FavoriteCategory(name ?? this.name, color ?? this.color);
}

/// 즐겨찾기 파일 전체(카테고리 목록 + 포인트).
class FavoriteData {
  final List<FavoriteCategory> categories;
  final List<FavoritePoint> points;

  const FavoriteData({this.categories = const [], this.points = const []});

  FavoriteCategory? category(String name) {
    for (final c in categories) {
      if (c.name == name) return c;
    }
    return null;
  }

  int colorOf(String category) =>
      this.category(category)?.color ?? FavoriteStore.palette.first;

  /// 다음 새 카테고리에 줄 색(아직 안 쓴 팔레트 색 우선).
  int nextColor() {
    final used = categories.map((c) => c.color).toSet();
    for (final c in FavoriteStore.palette) {
      if (!used.contains(c)) return c;
    }
    return FavoriteStore.palette[categories.length % FavoriteStore.palette.length];
  }

  FavoriteData copyWith({
    List<FavoriteCategory>? categories,
    List<FavoritePoint>? points,
  }) =>
      FavoriteData(
        categories: categories ?? this.categories,
        points: points ?? this.points,
      );
}

/// 저장 폴더의 `즐겨찾기.md`에 즐겨찾기를 카테고리(## 제목)별로 모아 둔다.
/// 형식(사람이 읽을 수 있게 + 좌표·색은 숨김 주석):
/// ```
/// # ⭐ 즐겨찾기
///
/// ## 미지정
/// [//]: # (cat:color=#FFB300)
/// - 이름 | 메모
///   [//]: # (fav:37.0012345, 126.4567890 | 2026-11-25 14:30)
/// ```
/// 제목 없이 있는 포인트(이전 형식)와 '## 기본'(이전 이름)은 '미지정' 카테고리로 읽는다.
/// 날짜 이름 파일이 아니라 날짜 목록·검색에는 나타나지 않고, 메모 백업에는 함께 올라간다.
class FavoriteStore {
  static const fileName = '즐겨찾기.md';
  /// 카테고리를 정하지 않은 즐겨찾기. 이름 변경·삭제 불가, 목록 맨 아래에 둔다.
  static const defaultCategory = '미지정';
  static const _legacyDefault = '기본'; // 이전 이름 — 읽을 때 미지정으로

  /// 표시·저장 순서: '미지정'은 항상 맨 아래.
  static List<FavoriteCategory> ordered(List<FavoriteCategory> cats) => [
        ...cats.where((c) => c.name != defaultCategory),
        ...cats.where((c) => c.name == defaultCategory),
      ];

  /// 카테고리 마커 색(새 카테고리에 차례로 배정).
  static const palette = <int>[
    0xFFFFB300, // 주황(기본)
    0xFF1E88E5, // 파랑
    0xFF43A047, // 초록
    0xFFE53935, // 빨강
    0xFF8E24AA, // 보라
    0xFF00ACC1, // 청록
    0xFFF4511E, // 진주황
    0xFF6D4C41, // 갈색
  ];

  final _saf = SafService();

  static final _favRe = RegExp(
      r'^\[//\]: # \(fav:(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)\s*\|\s*(\d{4}-\d{2}-\d{2}(?: \d{2}:\d{2})?)\)$');
  static final _catRe = RegExp(r'^\[//\]: # \(cat:color=#([0-9A-Fa-f]{6})\)$');

  Future<FavoriteData> load(String savePath) async {
    if (savePath.isEmpty) return const FavoriteData();
    try {
      String? content;
      if (SafService.isSafUri(savePath)) {
        content = await _saf.readFile(savePath, fileName);
      } else {
        final f = File('$savePath/$fileName');
        if (await f.exists()) content = await f.readAsString();
      }
      return content == null ? const FavoriteData() : parse(content);
    } catch (_) {
      return const FavoriteData();
    }
  }

  Future<void> save(String savePath, FavoriteData data) async {
    final content = build(data);
    if (SafService.isSafUri(savePath)) {
      await _saf.writeFile(savePath, fileName, content);
    } else {
      final f = File('$savePath/$fileName');
      await f.parent.create(recursive: true);
      await f.writeAsString(content);
    }
  }

  static FavoriteData parse(String content) {
    final cats = <FavoriteCategory>[];
    final points = <FavoritePoint>[];
    void ensureCat(String name, [int? color]) {
      final i = cats.indexWhere((c) => c.name == name);
      if (i < 0) {
        cats.add(FavoriteCategory(
            name, color ?? FavoriteData(categories: cats).nextColor()));
      } else if (color != null) {
        cats[i] = cats[i].copyWith(color: color);
      }
    }

    var current = defaultCategory;
    String? visible; // 직전 '- 이름 | 메모' 줄
    for (final raw in content.split('\n')) {
      final line = raw.trim();
      if (line.startsWith('## ')) {
        current = clean(line.substring(3));
        if (current.isEmpty || current == _legacyDefault) current = defaultCategory;
        ensureCat(current);
        visible = null;
        continue;
      }
      final cm = _catRe.firstMatch(line);
      if (cm != null) {
        ensureCat(current, 0xFF000000 | int.parse(cm.group(1)!, radix: 16));
        continue;
      }
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
      ensureCat(current);
      points.add(FavoritePoint(
        name: (sep < 0 ? visible : visible.substring(0, sep)).trim(),
        memo: sep < 0 ? '' : visible.substring(sep + 3).trim(),
        lat: lat,
        lng: lng,
        created: created ?? DateTime.now(),
        category: current,
      ));
      visible = null;
    }
    return FavoriteData(categories: ordered(cats), points: points);
  }

  static String build(FavoriteData data) {
    // 포인트가 참조하는데 목록에 없는 카테고리도 빠뜨리지 않는다.
    var cats = [...data.categories];
    for (final p in data.points) {
      if (!cats.any((c) => c.name == p.category)) {
        cats.add(FavoriteCategory(
            p.category, FavoriteData(categories: cats).nextColor()));
      }
    }
    cats = ordered(cats);
    final sb = StringBuffer('# ⭐ 즐겨찾기\n');
    for (final c in cats) {
      final hex = (c.color & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
      sb.write('\n## ${clean(c.name)}\n[//]: # (cat:color=#$hex)\n');
      for (final p in data.points.where((p) => p.category == c.name)) {
        sb.write('- ${clean(p.name)}');
        if (p.memo.trim().isNotEmpty) sb.write(' | ${clean(p.memo)}');
        sb.write('\n  [//]: # (fav:${p.lat.toStringAsFixed(7)}, '
            '${p.lng.toStringAsFixed(7)} | ${formatCreated(p.created)})\n');
      }
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

  /// 복원 병합: 로컬 + 드라이브의 합집합. 카테고리는 이름 기준(로컬 순서·색 우선),
  /// 포인트는 좌표·이름 기준(로컬 우선 — 카테고리가 다르면 로컬 쪽).
  static String merge(String local, String remote) {
    final l = parse(local);
    final r = parse(remote);
    final cats = [...l.categories];
    for (final c in r.categories) {
      if (!cats.any((x) => x.name == c.name)) cats.add(c);
    }
    final merged = <String, FavoritePoint>{};
    for (final p in r.points) {
      merged[p.key] = p;
    }
    for (final p in l.points) {
      merged[p.key] = p;
    }
    return build(FavoriteData(categories: cats, points: merged.values.toList()));
  }
}
