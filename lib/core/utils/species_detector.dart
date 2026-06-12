import '../constants/app_constants.dart';

/// 메모 텍스트에서 알려진 어종 이름을 찾아 반환.
///
/// [species] 목록(기본값 `kCommonFishSpecies`) 중에서 탐색한다.
/// 규칙: 가장 먼저 등장하는 어종을 선택하고, 같은 위치에서 시작하면
/// 더 긴(구체적인) 이름을 우선한다. (예: "쥐노래미"가 "노래미"보다 우선)
/// 일치하는 어종이 없으면 null.
String? detectFishSpecies(String text, [List<String>? species]) {
  if (text.isEmpty) return null;
  final list = species ?? kCommonFishSpecies;
  String? best;
  int bestPos = 1 << 30;
  for (final s in list) {
    final idx = text.indexOf(s);
    if (idx < 0) continue;
    if (idx < bestPos ||
        (idx == bestPos && (best == null || s.length > best.length))) {
      bestPos = idx;
      best = s;
    }
  }
  return best;
}

/// 길이 단위(cm·센치·센티·짜리 등)가 붙은 숫자를 찾는다.
final _lengthRe = RegExp(
  r'(\d+(?:\.\d+)?)\s*(?:cm|㎝|센티미터|센티|센치|짜리)',
  caseSensitive: false,
);

/// 메모 텍스트에서 물고기 길이(cm)를 추출.
///
/// "38cm", "38 센치", "38.5센티", "38짜리" 등에서 숫자를 인식한다.
/// 가장 먼저 등장하고 1~300cm 범위인 값을 반환. 없으면 null.
double? detectFishLength(String text) {
  if (text.isEmpty) return null;
  for (final m in _lengthRe.allMatches(text)) {
    final v = double.tryParse(m.group(1)!);
    if (v != null && v >= 1 && v <= 300) return v;
  }
  return null;
}
