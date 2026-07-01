/// 하루(출조) 단위 정보 — 태클 세트 + 최종 조과.
/// Phase 3에서 선사 정보가 여기에 추가된다.
/// 날짜 .md 헤더 뒤에 숨김 주석(JSON)으로 저장되어 백업/복원에 함께 실린다.
class TackleSet {
  final String rod; // 로드
  final String reel; // 릴
  final String line; // 라인
  final String rig; // 채비

  const TackleSet({
    this.rod = '',
    this.reel = '',
    this.line = '',
    this.rig = '',
  });

  bool get isEmpty =>
      rod.isEmpty && reel.isEmpty && line.isEmpty && rig.isEmpty;

  TackleSet copyWith({String? rod, String? reel, String? line, String? rig}) =>
      TackleSet(
        rod: rod ?? this.rod,
        reel: reel ?? this.reel,
        line: line ?? this.line,
        rig: rig ?? this.rig,
      );

  Map<String, dynamic> toJson() =>
      {'rod': rod, 'reel': reel, 'line': line, 'rig': rig};

  factory TackleSet.fromJson(Map<String, dynamic> j) => TackleSet(
        rod: j['rod'] as String? ?? '',
        reel: j['reel'] as String? ?? '',
        line: j['line'] as String? ?? '',
        rig: j['rig'] as String? ?? '',
      );
}

/// 최종 조과 항목: 어종 + 마릿수
class CatchTally {
  final String species;
  final int count;

  const CatchTally({required this.species, this.count = 1});

  CatchTally copyWith({String? species, int? count}) =>
      CatchTally(species: species ?? this.species, count: count ?? this.count);

  Map<String, dynamic> toJson() => {'species': species, 'count': count};

  factory CatchTally.fromJson(Map<String, dynamic> j) => CatchTally(
        species: j['species'] as String? ?? '',
        count: (j['count'] as num?)?.toInt() ?? 1,
      );
}

class OutingInfo {
  final List<TackleSet> tackles; // 최대 3
  final List<CatchTally> catches; // 최대 5

  const OutingInfo({this.tackles = const [], this.catches = const []});

  /// 저장할 내용이 없는지(태클 전부 비어있고 조과도 없음)
  bool get isEmpty => tackles.every((t) => t.isEmpty) && catches.isEmpty;

  OutingInfo copyWith({List<TackleSet>? tackles, List<CatchTally>? catches}) =>
      OutingInfo(
        tackles: tackles ?? this.tackles,
        catches: catches ?? this.catches,
      );

  Map<String, dynamic> toJson() => {
        'tackles': tackles.map((t) => t.toJson()).toList(),
        'catches': catches.map((c) => c.toJson()).toList(),
      };

  factory OutingInfo.fromJson(Map<String, dynamic> j) => OutingInfo(
        tackles: (j['tackles'] as List?)
                ?.map((e) => TackleSet.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        catches: (j['catches'] as List?)
                ?.map((e) => CatchTally.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}
