import 'dart:math';

import '../domain/models/tide_station.dart';

/// 천체 출몰 결과(해당 일자 로컬 기준). rise/set이 null이면 종일 떠있거나 종일 안 뜸.
class RiseSet {
  final DateTime? rise;
  final DateTime? set;
  const RiseSet(this.rise, this.set);
}

/// 달 위상: age(0~29.53일), illumination(0~1), 한국어 위상명
class MoonPhase {
  final double age;
  final double illumination;
  final String name;
  const MoonPhase(this.age, this.illumination, this.name);
}

double _rad(double d) => d * pi / 180.0;
double _frac(double x) => x - x.floorToDouble();

const double _twoPi = 2 * pi;
const double _arc = 206264.8062; // 초각(arcsec) → rad 변환 상수
const double _cosEps = 0.91748; // cos(23.43929°)
const double _sinEps = 0.39778; // sin(23.43929°)

// ── 태양/달 저정밀 위치 (Montenbruck & Pfleger) ──────────────
// 반환: [적경 ra(시간), 적위 dec(도)]

List<double> _miniSun(double t) {
  final m = _twoPi * _frac(0.993133 + 99.997361 * t);
  final l = _twoPi *
      _frac(0.7859453 +
          m / _twoPi +
          (6893.0 * sin(m) + 72.0 * sin(2 * m) + 6191.2 * t) / 1296.0e3);
  final sl = sin(l);
  final x = cos(l);
  final y = _cosEps * sl;
  final z = _sinEps * sl;
  final rho = sqrt(1.0 - z * z);
  final dec = (360.0 / _twoPi) * atan(z / rho);
  var ra = (48.0 / _twoPi) * atan(y / (x + rho));
  if (ra < 0) ra += 24.0;
  return [ra, dec];
}

List<double> _miniMoon(double t) {
  final l0 = _frac(0.606433 + 1336.855225 * t); // 평균황경(회전수)
  final l = _twoPi * _frac(0.374897 + 1325.552410 * t); // 달 평균근점이각
  final ls = _twoPi * _frac(0.993133 + 99.997361 * t); // 태양 평균근점이각
  final d = _twoPi * _frac(0.827361 + 1236.853086 * t); // 이각
  final f = _twoPi * _frac(0.259086 + 1342.227825 * t); // 승교점 거리

  final dl = 22640.0 * sin(l) -
      4586.0 * sin(l - 2 * d) +
      2370.0 * sin(2 * d) +
      769.0 * sin(2 * l) -
      668.0 * sin(ls) -
      412.0 * sin(2 * f) -
      212.0 * sin(2 * l - 2 * d) -
      206.0 * sin(l + ls - 2 * d) +
      192.0 * sin(l + 2 * d) -
      165.0 * sin(ls - 2 * d) -
      125.0 * sin(d) -
      110.0 * sin(l + ls) +
      148.0 * sin(l - ls) -
      55.0 * sin(2 * f - 2 * d);

  final s = f + (dl + 412.0 * sin(2 * f) + 541.0 * sin(ls)) / _arc;
  final h = f - 2 * d;
  final n = -526.0 * sin(h) +
      44.0 * sin(l + h) -
      31.0 * sin(-l + h) -
      23.0 * sin(ls + h) +
      11.0 * sin(-ls + h) -
      25.0 * sin(-2 * l + f) +
      21.0 * sin(-l + f);

  final lMoon = _twoPi * _frac(l0 + dl / 1296.0e3); // 황경(rad)
  final bMoon = (18520.0 * sin(s) + n) / _arc; // 황위(rad)

  final cb = cos(bMoon);
  final x = cb * cos(lMoon);
  final v = cb * sin(lMoon);
  final w = sin(bMoon);
  final y = _cosEps * v - _sinEps * w;
  final z = _sinEps * v + _cosEps * w;
  final rho = sqrt(1.0 - z * z);
  final dec = (360.0 / _twoPi) * atan(z / rho);
  var ra = (48.0 / _twoPi) * atan(y / (x + rho));
  if (ra < 0) ra += 24.0;
  return [ra, dec];
}

// 지방 평균 항성시(시간). lng는 동경 양수(도).
double _lmst(double mjd, double lng) {
  final mjd0 = mjd.floorToDouble();
  final ut = (mjd - mjd0) * 24.0;
  final t = (mjd0 - 51544.5) / 36525.0;
  final gmst = 6.697374558 +
      1.0027379093 * ut +
      (8640184.812866 + (0.093104 - 6.2e-6 * t) * t) * t / 3600.0;
  var lmst = (gmst + lng / 15.0) % 24.0;
  if (lmst < 0) lmst += 24.0;
  return lmst;
}

// 지정 시각의 천체 고도 sin값 - 목표고도 sin값
double _sinAlt(double mjd0, double hours, double lng, double cphi, double sphi,
    List<double> Function(double) obj) {
  final mjd = mjd0 + hours / 24.0;
  final t = (mjd - 51544.5) / 36525.0;
  final rd = obj(t);
  final ra = rd[0];
  final dec = rd[1];
  final tau = 15.0 * (_lmst(mjd, lng) - ra); // 시간각(도)
  return sphi * sin(_rad(dec)) + cphi * cos(_rad(dec)) * cos(_rad(tau));
}

// 2차 보간(Montenbruck Quad): [-1,1] 구간 근 개수와 위치
class _Quad {
  final int nz;
  final double z1;
  final double z2;
  final double ye;
  const _Quad(this.nz, this.z1, this.z2, this.ye);
}

_Quad _quad(double ym, double y0, double yp) {
  final a = 0.5 * (ym + yp) - y0;
  final b = 0.5 * (yp - ym);
  final c = y0;
  final xe = -b / (2 * a);
  final ye = (a * xe + b) * xe + c;
  final dis = b * b - 4 * a * c;
  int nz = 0;
  double z1 = 0, z2 = 0;
  if (dis >= 0) {
    final dx = 0.5 * sqrt(dis) / a.abs();
    z1 = xe - dx;
    z2 = xe + dx;
    if (z1.abs() <= 1.0) nz++;
    if (z2.abs() <= 1.0) nz++;
    if (z1 < -1.0) z1 = z2;
  }
  return _Quad(nz, z1, z2, ye);
}

RiseSet _riseSet(DateTime localMidnight, double lat, double lng, double sinh0,
    List<double> Function(double) obj) {
  // 로컬 자정의 UT MJD
  final mjd0 = localMidnight.millisecondsSinceEpoch / 86400000.0 + 40587.0;
  final sphi = sin(_rad(lat));
  final cphi = cos(_rad(lat));

  DateTime at(double hour) =>
      localMidnight.add(Duration(seconds: (hour * 3600).round()));

  double ym = _sinAlt(mjd0, 0, lng, cphi, sphi, obj) - sinh0;
  DateTime? rise;
  DateTime? set;
  double hour = 1.0;
  while (hour < 24.5 && (rise == null || set == null)) {
    final y0 = _sinAlt(mjd0, hour, lng, cphi, sphi, obj) - sinh0;
    final yp = _sinAlt(mjd0, hour + 1, lng, cphi, sphi, obj) - sinh0;
    final q = _quad(ym, y0, yp);
    if (q.nz == 1) {
      if (ym < 0) {
        rise ??= at(hour + q.z1);
      } else {
        set ??= at(hour + q.z1);
      }
    } else if (q.nz == 2) {
      if (q.ye < 0) {
        rise ??= at(hour + q.z2);
        set ??= at(hour + q.z1);
      } else {
        rise ??= at(hour + q.z1);
        set ??= at(hour + q.z2);
      }
    }
    ym = yp;
    hour += 2.0;
  }
  return RiseSet(rise, set);
}

/// 일출/일몰 (로컬). 표준 고도 -0.833°.
RiseSet sunRiseSet(DateTime localDay, double lat, double lng) {
  final midnight = DateTime(localDay.year, localDay.month, localDay.day);
  return _riseSet(midnight, lat, lng, sin(_rad(-0.833)), _miniSun);
}

/// 월출/월몰 (로컬, 근사). 표준 고도 +0.133°(시차·굴절 보정 근사).
RiseSet moonRiseSet(DateTime localDay, double lat, double lng) {
  final midnight = DateTime(localDay.year, localDay.month, localDay.day);
  return _riseSet(midnight, lat, lng, sin(_rad(0.133)), _miniMoon);
}

/// 달 위상(월령·조도·이름). 알려진 삭(2000-01-06 18:14 UTC) 기준 근사.
MoonPhase moonPhase(DateTime date) {
  final jd = date.toUtc().millisecondsSinceEpoch / 86400000.0 + 2440587.5;
  const synodic = 29.530588853;
  const newMoonRef = 2451550.1;
  var age = (jd - newMoonRef) % synodic;
  if (age < 0) age += synodic;
  final illum = (1 - cos(_twoPi * age / synodic)) / 2.0;
  return MoonPhase(age, illum, _phaseName(age));
}

String _phaseName(double age) {
  if (age < 1.84566) return '삭';
  if (age < 5.53699) return '초승달';
  if (age < 9.22831) return '상현달';
  if (age < 12.91963) return '차오르는 달';
  if (age < 16.61096) return '보름';
  if (age < 20.30228) return '기우는 달';
  if (age < 23.99361) return '하현달';
  if (age < 27.68493) return '그믐달';
  return '삭';
}

/// 당일 조차(만조-간조 범위)와 근사 물흐름%.
class TideRange {
  final int rangeCm; // 최고만조 - 최저간조
  final int percent; // 근사 물흐름%(인천 기준식)
  const TideRange(this.rangeCm, this.percent);
}

/// 그날 만조/간조 조위로 조차(cm)와 근사 물흐름%를 계산.
/// 물흐름%는 인천 데이터 역산식(% ≈ 0.164×조차 − 55)이라 타 관측소는 부정확할 수 있음.
/// 자료 부족(조위 2개 미만) 시 null.
TideRange? tidalRange(List<TideEvent> tides) {
  final levels =
      tides.where((t) => t.level != null).map((t) => t.level!).toList();
  if (levels.length < 2) return null;
  var maxL = levels.first;
  var minL = levels.first;
  for (final l in levels) {
    if (l > maxL) maxL = l;
    if (l < minL) minL = l;
  }
  final range = maxL - minL;
  final pct = (0.164 * range - 55).round().clamp(0, 100);
  return TideRange(range, pct);
}
