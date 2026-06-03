import 'package:flutter_test/flutter_test.dart';
import 'package:vo_rec/features/memo/data/md_serializer.dart';
import 'package:vo_rec/features/memo/domain/models/memo_entry.dart';
import 'package:vo_rec/features/location/domain/models/location_status.dart';

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
      expect(result, contains('### 09:05 | 🛰 37.1234, 127.5678'));
      expect(result, contains('낚시 포인트 메모'));
    });

    test('serializeEntry: GPS 없는 메모 → 헤더에 좌표 없음', () {
      final entry = MemoEntry(
        timestamp: DateTime(2026, 6, 2, 14, 30),
        text: 'GPS 없는 메모',
      );
      final result = MdSerializer.serializeEntry(entry);
      expect(result, contains('### 14:30\n'));
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

    test('serializeLocationBlock: 최초 현황 → ## 현황 포함, 주소 표시', () {
      final loc = LocationStatus(
        timestamp: DateTime(2026, 6, 2, 8, 0),
        address: '경기도 가평군',
        isMove: false,
      );
      final result = MdSerializer.serializeLocationBlock(loc);
      expect(result, contains('## 현황'));
      expect(result, isNot(contains('이동')));
      expect(result, contains('경기도 가평군'));
    });

    test('serializeLocationBlock: 이동 현황 → ## 현황 (HH:mm 이동) 포함', () {
      final loc = LocationStatus(
        timestamp: DateTime(2026, 6, 2, 11, 30),
        address: '강원도 춘천시',
        isMove: true,
      );
      final result = MdSerializer.serializeLocationBlock(loc);
      expect(result, contains('## 현황 (11:30 이동)'));
      expect(result, contains('강원도 춘천시'));
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
      final blocks = MdSerializer.parseBlocks(content);
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
      final blocks = MdSerializer.parseBlocks(content);
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
      final blocks = MdSerializer.parseBlocks(content);
      expect(blocks.length, 1);
      final loc = blocks[0] as LocationStatus;
      expect(loc.isMove, isFalse);
      expect(loc.address, '경기도 가평군');
    });

    test('parseBlocks: 이동 현황 블록 파싱 → isMove=true', () {
      const content = '''
## 현황 (11:30 이동)
- 📍 강원도 춘천시
- 🌡 기온: -°C | 🌊 -물 (- --:--) | 💧 수온 -°C
- 관측소: - (-.--km)
''';
      final blocks = MdSerializer.parseBlocks(content);
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
      final blocks = MdSerializer.parseBlocks(serialized);
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
      final blocks = MdSerializer.parseBlocks(serialized);
      expect(blocks.length, 1);
      final parsed = blocks[0] as MemoEntry;
      expect(parsed.isPhoto, isTrue);
      expect(parsed.photoPath, original.photoPath);
    });
  });
}
