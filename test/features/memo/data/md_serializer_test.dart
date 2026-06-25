import 'package:flutter_test/flutter_test.dart';
import 'package:nakkda/features/memo/data/md_serializer.dart';
import 'package:nakkda/features/memo/domain/models/memo_entry.dart';
import 'package:nakkda/features/location/domain/models/location_status.dart';
import 'package:nakkda/features/tide/domain/models/tide_station.dart';
import 'package:nakkda/core/services/tracking_service.dart';

void main() {
  group('MdSerializer 쓰기', () {
    test('serializeEntry: GPS 있는 텍스트 메모 → 헤더에 🛰 lat, lng 포함', () {
      final entry = MemoEntry(
        timestamp: DateTime(2026, 6, 2, 9, 5),
        latitude: 37.1234,
        longitude: 127.5678,
        text: '낚시 포인트 메모',
      );
      final result = MdSerializer.serializeEntry(entry);
      expect(result, contains('### 2026-06-02 09:05:00 | 🛰 37.1234, 127.5678'));
      expect(result, contains('낚시 포인트 메모'));
    });

    test('serializeEntry: GPS 없는 메모 → 헤더에 좌표 없음', () {
      final entry = MemoEntry(
        timestamp: DateTime(2026, 6, 2, 14, 30),
        text: 'GPS 없는 메모',
      );
      final result = MdSerializer.serializeEntry(entry);
      expect(result, contains('### 2026-06-02 14:30:00\n'));
      expect(result, isNot(contains('🛰')));
      expect(result, contains('GPS 없는 메모'));
    });

    test('serializeEntry: 사진 메모 → ![](photos/...) 포함', () {
      final entry = MemoEntry(
        timestamp: DateTime(2026, 6, 2, 10, 0),
        photoPath: 'photos/20260602_100000.jpg',
      );
      final result = MdSerializer.serializeEntry(entry);
      expect(result, contains('![](photos/20260602_100000.jpg)'));
    });

    test('serializeLocationBlock: 자동(isMove=false) 현황도 시각 표기로 통일', () {
      final loc = LocationStatus(
        timestamp: DateTime(2026, 6, 2, 8, 0),
        address: '경기도 가평군',
        isMove: false,
      );
      final result = MdSerializer.serializeLocationBlock(loc);
      expect(result, contains('## 현황 (08:00)'));
      expect(result, isNot(contains('장소')));
      expect(result, contains('경기도 가평군'));
    });

    test('serializeLocationBlock: 수동(isMove=true) 현황도 동일 포맷(장소 단어 없음)', () {
      final loc = LocationStatus(
        timestamp: DateTime(2026, 6, 2, 11, 30),
        address: '강원도 춘천시',
        isMove: true,
      );
      final result = MdSerializer.serializeLocationBlock(loc);
      expect(result, contains('## 현황 (11:30)'));
      expect(result, isNot(contains('장소')));
      expect(result, contains('강원도 춘천시'));
    });

    test('serializeLocationBlock: 당일 물때 → tides 숨김 주석으로 보존', () {
      final loc = LocationStatus(
        timestamp: DateTime(2026, 6, 2, 8, 0),
        address: '인천 연안',
        tides: const [
          TideEvent(type: '만조', time: '06:12', level: 721),
          TideEvent(type: '간조', time: '12:30', level: 123),
        ],
      );
      final result = MdSerializer.serializeLocationBlock(loc);
      expect(result,
          contains('[//]: # (tides:만조 06:12 721,간조 12:30 123)'));
    });

    test('fileHeader: # 2026-06-02 포함', () {
      final date = DateTime(2026, 6, 2);
      final result = MdSerializer.fileHeader(date);
      expect(result, contains('# 2026-06-02'));
    });
  });

  group('MdSerializer 읽기', () {
    test('parseBlocks: 텍스트 메모 블록 파싱 → MemoEntry 반환, GPS 좌표 파싱', () {
      const content = '''
---

### 09:05 | 🛰 37.1234, 127.5678
낚시 포인트 메모
''';
      final blocks = MdSerializer.parseBlocks(content, DateTime(2026, 6, 2));
      expect(blocks.length, 1);
      final entry = blocks[0] as MemoEntry;
      expect(entry.timeLabel, '09:05');
      expect(entry.latitude, closeTo(37.1234, 0.0001));
      expect(entry.longitude, closeTo(127.5678, 0.0001));
      expect(entry.text, '낚시 포인트 메모');
      expect(entry.isPhoto, isFalse);
    });

    test('parseBlocks: 사진 메모 블록 파싱 → photoPath 추출', () {
      const content = '''
---

### 10:00
![](photos/20260602_100000.jpg)
''';
      final blocks = MdSerializer.parseBlocks(content, DateTime(2026, 6, 2));
      expect(blocks.length, 1);
      final entry = blocks[0] as MemoEntry;
      expect(entry.isPhoto, isTrue);
      expect(entry.photoPath, 'photos/20260602_100000.jpg');
      expect(entry.text, isNull);
    });

    test('parseBlocks: 현황 블록 파싱 → LocationStatus 반환', () {
      const content = '''
## 현황
- 📍 경기도 가평군
- 🌡 기온: -°C | 🌊 -물 (- --:--) | 💧 수온 -°C
- 관측소: - (-.--km)
''';
      final blocks = MdSerializer.parseBlocks(content, DateTime(2026, 6, 2));
      expect(blocks.length, 1);
      final loc = blocks[0] as LocationStatus;
      expect(loc.isMove, isFalse);
      expect(loc.address, '경기도 가평군');
    });

    test('parseBlocks: 통일 포맷(## 현황 (HH:mm)) → timestamp 복원', () {
      const content = '''
## 현황 (08:15)
- 📍 인천 연안
- 관측소: 인천 (50.3km) | 🌊 5물 (만조 18:03)
''';
      final blocks = MdSerializer.parseBlocks(content, DateTime(2026, 6, 2));
      expect(blocks.length, 1);
      final loc = blocks[0] as LocationStatus;
      expect(loc.timestamp, DateTime(2026, 6, 2, 8, 15));
      expect(loc.address, '인천 연안');
    });

    test('parseBlocks: tides 숨김 주석 → 당일 물때 왕복', () {
      final original = LocationStatus(
        timestamp: DateTime(2026, 6, 2, 8, 0),
        address: '인천 연안',
        stationName: '인천',
        stationDistance: 50.3,
        tides: const [
          TideEvent(type: '만조', time: '06:12', level: 721),
          TideEvent(type: '간조', time: '12:30', level: 123),
          TideEvent(type: '만조', time: '18:03'),
        ],
      );
      final serialized = MdSerializer.serializeLocationBlock(original);
      final blocks = MdSerializer.parseBlocks(serialized, DateTime(2026, 6, 2));
      expect(blocks.length, 1);
      final loc = blocks[0] as LocationStatus;
      expect(loc.tides.length, 3);
      expect(loc.tides[0].type, '만조');
      expect(loc.tides[0].time, '06:12');
      expect(loc.tides[0].level, 721);
      expect(loc.tides[2].time, '18:03');
      expect(loc.tides[2].level, isNull);
    });

    test('parseBlocks: 이동 현황 블록 파싱 → isMove=true', () {
      const content = '''
## 현황 (11:30 이동)
- 📍 강원도 춘천시
- 🌡 기온: -°C | 🌊 -물 (- --:--) | 💧 수온 -°C
- 관측소: - (-.--km)
''';
      final blocks = MdSerializer.parseBlocks(content, DateTime(2026, 6, 2));
      expect(blocks.length, 1);
      final loc = blocks[0] as LocationStatus;
      expect(loc.isMove, isTrue);
      expect(loc.address, '강원도 춘천시');
    });

    test('parseBlocks: 쓰기 후 읽기 왕복(roundtrip) — 텍스트 메모', () {
      final original = MemoEntry(
        timestamp: DateTime(2026, 6, 2, 9, 5),
        latitude: 37.1234,
        longitude: 127.5678,
        text: '왕복 테스트 메모',
      );
      final serialized = MdSerializer.serializeEntry(original);
      final blocks = MdSerializer.parseBlocks(serialized, DateTime(2026, 6, 2));
      expect(blocks.length, 1);
      final parsed = blocks[0] as MemoEntry;
      expect(parsed.timeLabel, original.timeLabel);
      expect(parsed.latitude, closeTo(original.latitude!, 0.0001));
      expect(parsed.longitude, closeTo(original.longitude!, 0.0001));
      expect(parsed.text, original.text);
    });

    test('parseBlocks: 쓰기 후 읽기 왕복(roundtrip) — 사진 메모', () {
      final original = MemoEntry(
        timestamp: DateTime(2026, 6, 2, 10, 0),
        photoPath: 'photos/20260602_100000.jpg',
      );
      final serialized = MdSerializer.serializeEntry(original);
      final blocks = MdSerializer.parseBlocks(serialized, DateTime(2026, 6, 2));
      expect(blocks.length, 1);
      final parsed = blocks[0] as MemoEntry;
      expect(parsed.isPhoto, isTrue);
      expect(parsed.photoPath, original.photoPath);
    });
  });

  group('MdSerializer 조과(어종)', () {
    test('serializeEntry: 어종 → - 🐟 감성돔 (마릿수 없음)', () {
      final entry = MemoEntry(
        timestamp: DateTime(2026, 6, 2, 9, 5),
        fishSpecies: '감성돔',
      );
      final result = MdSerializer.serializeEntry(entry);
      expect(result, contains('- 🐟 감성돔'));
      expect(result, isNot(contains('마리')));
    });

    test('serializeEntry: 조과 정보 없으면 🐟 줄 없음', () {
      final entry = MemoEntry(
        timestamp: DateTime(2026, 6, 2, 9, 5),
        text: '입질 없음',
      );
      final result = MdSerializer.serializeEntry(entry);
      expect(result, isNot(contains('🐟')));
    });

    test('parseBlocks: 어종 + 길이 + 텍스트 동시 파싱', () {
      const content = '''
---

### 2026-06-02 09:05:00 | 🛰 37.1234, 127.5678
- 📏 38.5cm
- 🐟 감성돔
오늘 조황 좋음
''';
      final blocks = MdSerializer.parseBlocks(content, DateTime(2026, 6, 2));
      expect(blocks.length, 1);
      final entry = blocks[0] as MemoEntry;
      expect(entry.fishSpecies, '감성돔');
      expect(entry.fishLength, closeTo(38.5, 0.001));
      expect(entry.text, '오늘 조황 좋음');
    });

    test('parseBlocks: 공백 포함 어종도 파싱 (- 🐟 무늬 오징어)', () {
      const content = '''
---

### 2026-06-02 09:05:00
- 🐟 무늬 오징어
''';
      final blocks = MdSerializer.parseBlocks(content, DateTime(2026, 6, 2));
      final entry = blocks[0] as MemoEntry;
      expect(entry.fishSpecies, '무늬 오징어');
    });

    test('parseBlocks: 구 포맷 "N마리" 접미사는 무시하고 어종만 추출', () {
      const content = '''
---

### 2026-06-02 09:05:00
- 🐟 감성돔 2마리
''';
      final blocks = MdSerializer.parseBlocks(content, DateTime(2026, 6, 2));
      final entry = blocks[0] as MemoEntry;
      expect(entry.fishSpecies, '감성돔');
    });

    test('parseBlocks: 쓰기 후 읽기 왕복(roundtrip) — 조과', () {
      final original = MemoEntry(
        timestamp: DateTime(2026, 6, 2, 9, 5),
        fishSpecies: '참돔',
        fishLength: 42.0,
        text: '대박',
      );
      final serialized = MdSerializer.serializeEntry(original);
      final blocks = MdSerializer.parseBlocks(serialized, DateTime(2026, 6, 2));
      final parsed = blocks[0] as MemoEntry;
      expect(parsed.fishSpecies, '참돔');
      expect(parsed.fishLength, closeTo(42.0, 0.001));
      expect(parsed.text, '대박');
    });

    test('parseBlocks: 구 포맷(조과 줄 없음) 하위호환 — fishSpecies null', () {
      const content = '''
---

### 09:05 | 🛰 37.1234, 127.5678
기존 메모
''';
      final blocks = MdSerializer.parseBlocks(content, DateTime(2026, 6, 2));
      final entry = blocks[0] as MemoEntry;
      expect(entry.fishSpecies, isNull);
      expect(entry.text, '기존 메모');
    });
  });

  group('MdSerializer 트래킹 포인트', () {
    test('trackCommentsFor: 메모와 동일한 날짜시각 | 🛰 GPS 순서로 기록', () {
      final line = MdSerializer.trackCommentsFor([
        TrackPoint(
            lat: 37.1234, lng: 127.5678, timestamp: DateTime(2026, 6, 2, 9, 5, 7)),
      ]);
      expect(line,
          contains('[//]: # (track:2026-06-02 09:05:07 | 🛰 37.1234, 127.5678)'));
    });

    test('parseTrackPoints: 신 포맷 왕복', () {
      final pts = [
        TrackPoint(
            lat: 37.1234, lng: 127.5678, timestamp: DateTime(2026, 6, 2, 9, 5, 7)),
      ];
      final parsed = MdSerializer.parseTrackPoints(MdSerializer.trackCommentsFor(pts));
      expect(parsed.length, 1);
      expect(parsed[0].lat, 37.1234);
      expect(parsed[0].lng, 127.5678);
      expect(parsed[0].timestamp, DateTime(2026, 6, 2, 9, 5, 7));
    });

    test('parseTrackPoints: 구 포맷(track:lat,lng,날짜시각) 하위호환', () {
      const old = '[//]: # (track:37.1234,127.5678,2026-06-02 09:05:07)\n';
      final parsed = MdSerializer.parseTrackPoints(old);
      expect(parsed.length, 1);
      expect(parsed[0].lat, 37.1234);
      expect(parsed[0].lng, 127.5678);
      expect(parsed[0].timestamp, DateTime(2026, 6, 2, 9, 5, 7));
    });
  });
}
