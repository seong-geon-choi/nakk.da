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

/// 선사(선박) 정보. 출항/입항 시간은 자정 기준 분.
class VesselInfo {
  final String name; // 선박명
  final String port; // 항구
  final int departMin; // 출항시간(분), 기본 300=05:00
  final int arriveMin; // 입항시간(분), 기본 960=16:00
  final String point; // 주요 포인트
  final String fishType; // 낚시 종류
  final double? avgDepth; // 평균 수심(m)
  final int rating; // 별점 0~5

  const VesselInfo({
    this.name = '',
    this.port = '',
    this.departMin = 300,
    this.arriveMin = 960,
    this.point = '',
    this.fishType = '',
    this.avgDepth,
    this.rating = 0,
  });

  bool get isEmpty =>
      name.isEmpty &&
      port.isEmpty &&
      point.isEmpty &&
      fishType.isEmpty &&
      avgDepth == null &&
      rating == 0;

  VesselInfo copyWith({
    String? name,
    String? port,
    int? departMin,
    int? arriveMin,
    String? point,
    String? fishType,
    double? avgDepth,
    int? rating,
  }) =>
      VesselInfo(
        name: name ?? this.name,
        port: port ?? this.port,
        departMin: departMin ?? this.departMin,
        arriveMin: arriveMin ?? this.arriveMin,
        point: point ?? this.point,
        fishType: fishType ?? this.fishType,
        avgDepth: avgDepth ?? this.avgDepth,
        rating: rating ?? this.rating,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'port': port,
        'departMin': departMin,
        'arriveMin': arriveMin,
        'point': point,
        'fishType': fishType,
        'avgDepth': avgDepth,
        'rating': rating,
      };

  factory VesselInfo.fromJson(Map<String, dynamic> j) => VesselInfo(
        name: j['name'] as String? ?? '',
        port: j['port'] as String? ?? '',
        departMin: (j['departMin'] as num?)?.toInt() ?? 300,
        arriveMin: (j['arriveMin'] as num?)?.toInt() ?? 960,
        point: j['point'] as String? ?? '',
        fishType: j['fishType'] as String? ?? '',
        avgDepth: (j['avgDepth'] as num?)?.toDouble(),
        rating: (j['rating'] as num?)?.toInt() ?? 0,
      );
}

class OutingInfo {
  final List<TackleSet> tackles; // 최대 3
  final List<CatchTally> catches; // 최대 5
  final VesselInfo? vessel;

  const OutingInfo(
      {this.tackles = const [], this.catches = const [], this.vessel});

  /// 저장할 내용이 없는지(태클·조과·선사 모두 비어있음)
  bool get isEmpty =>
      tackles.every((t) => t.isEmpty) &&
      catches.isEmpty &&
      (vessel == null || vessel!.isEmpty);

  OutingInfo copyWith(
          {List<TackleSet>? tackles,
          List<CatchTally>? catches,
          VesselInfo? vessel}) =>
      OutingInfo(
        tackles: tackles ?? this.tackles,
        catches: catches ?? this.catches,
        vessel: vessel ?? this.vessel,
      );

  Map<String, dynamic> toJson() => {
        'tackles': tackles.map((t) => t.toJson()).toList(),
        'catches': catches.map((c) => c.toJson()).toList(),
        if (vessel != null && !vessel!.isEmpty) 'vessel': vessel!.toJson(),
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
        vessel: j['vessel'] != null
            ? VesselInfo.fromJson(j['vessel'] as Map<String, dynamic>)
            : null,
      );
}
