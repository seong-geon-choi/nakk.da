import 'package:flutter_test/flutter_test.dart';
import 'package:lunar/lunar.dart';
import 'package:nakkda/features/tide/data/astro_calc.dart';
import 'package:nakkda/features/tide/domain/models/tide_station.dart';

// 검증 기준: 국립해양조사원 인천 2026-06-25 (그림)
//  일출 05:14 / 일몰 19:59, 월출 15:58 / 월몰 01:30, 음력 5.11
// 머신 시간대 KST(+0900) 가정.
const _incheonLat = 37.4508;
const _incheonLng = 126.5922;

int _min(DateTime d) => d.hour * 60 + d.minute;

void main() {
  group('astro_calc 일출/일몰 (인천 6/25)', () {
    final s = sunRiseSet(DateTime(2026, 6, 25), _incheonLat, _incheonLng);
    test('일출 ~05:14 (±5분)', () {
      expect(s.rise, isNotNull);
      expect((_min(s.rise!) - (5 * 60 + 14)).abs(), lessThanOrEqualTo(5));
    });
    test('일몰 ~19:59 (±5분)', () {
      expect(s.set, isNotNull);
      expect((_min(s.set!) - (19 * 60 + 59)).abs(), lessThanOrEqualTo(5));
    });
  });

  group('astro_calc 월출/월몰 (인천 6/25, 근사)', () {
    final m = moonRiseSet(DateTime(2026, 6, 25), _incheonLat, _incheonLng);
    test('월출 ~15:58 (±15분)', () {
      expect(m.rise, isNotNull);
      expect((_min(m.rise!) - (15 * 60 + 58)).abs(), lessThanOrEqualTo(15));
    });
    test('월몰 ~01:30 (±15분)', () {
      expect(m.set, isNotNull);
      expect((_min(m.set!) - (1 * 60 + 30)).abs(), lessThanOrEqualTo(15));
    });
  });

  test('음력 변환: 2026-06-25 → 5.11', () {
    final lunar = Solar.fromYmd(2026, 6, 25).getLunar();
    expect(lunar.getMonth(), 5);
    expect(lunar.getDay(), 11);
  });

  group('물때(서해/인천) 음력일→물때 매핑', () {
    // 바다타임 인천 검증: 음력 10=1물, 11=2물, 16=7물(사리), 23=조금, 24=무시
    String label(int lunarDay) {
      final i = (lunarDay - 10) % 15;
      if (i <= 12) return '${i + 1}물';
      if (i == 13) return '조금';
      return '무시';
    }

    test('음력 11일 = 2물 (사용자 보고 사례)', () => expect(label(11), '2물'));
    test('음력 10일 = 1물', () => expect(label(10), '1물'));
    test('음력 15일 = 6물', () => expect(label(15), '6물'));
    test('음력 16일 = 7물(사리)', () => expect(label(16), '7물'));
    test('음력 23일 = 조금', () => expect(label(23), '조금'));
    test('음력 24일 = 무시', () => expect(label(24), '무시'));
    test('음력 25일 = 1물(주기 반복)', () => expect(label(25), '1물'));
    test('음력 1일 = 7물(그믐사리)', () => expect(label(1), '7물'));
  });

  test('달 위상: 음력 11일경 → 조도 70% 이상', () {
    final p = moonPhase(DateTime(2026, 6, 25, 12));
    expect(p.illumination, greaterThan(0.6));
    expect(p.age, greaterThan(8));
    expect(p.age, lessThan(14));
  });

  group('조차/근사 물흐름%', () {
    test('인천 6/25 조차 476cm → 약 23%', () {
      // 만조 704/658, 간조 322/228 → 최고704-최저228=476
      const tides = [
        TideEvent(type: '만조', time: '00:59', level: 704),
        TideEvent(type: '간조', time: '07:15', level: 322),
        TideEvent(type: '만조', time: '13:09', level: 658),
        TideEvent(type: '간조', time: '19:34', level: 228),
      ];
      final r = tidalRange(tides);
      expect(r, isNotNull);
      expect(r!.rangeCm, 476);
      expect(r.percent, 23);
    });

    test('인천 7/4 조차 762cm(최대) → 약 70%', () {
      const tides = [
        TideEvent(type: '만조', time: '07:15', level: 864),
        TideEvent(type: '간조', time: '01:07', level: 102),
        TideEvent(type: '만조', time: '19:30', level: 768),
        TideEvent(type: '간조', time: '13:44', level: 181),
      ];
      final r = tidalRange(tides);
      expect(r!.rangeCm, 762);
      expect(r.percent, 70);
    });

    test('조위 자료 부족 시 null', () {
      const tides = [TideEvent(type: '만조', time: '07:15', level: 864)];
      expect(tidalRange(tides), isNull);
    });
  });
}
