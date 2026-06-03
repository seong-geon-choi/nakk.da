import '../domain/models/tide_station.dart';

// 국립해양조사원 주요 조위관측소 목록
// 출처: https://www.khoa.go.kr (조위관측소 정보)
const List<TideStation> kTideStations = [
  // 서해 (West Coast)
  TideStation(code: 'DT_0001', name: '인천', latitude: 37.4508, longitude: 126.5922),
  TideStation(code: 'DT_0002', name: '안산', latitude: 37.1860, longitude: 126.6090),
  TideStation(code: 'DT_0003', name: '평택', latitude: 36.9710, longitude: 126.8260),
  TideStation(code: 'DT_0004', name: '보령', latitude: 36.4210, longitude: 126.4870),
  TideStation(code: 'DT_0005', name: '대천', latitude: 36.3280, longitude: 126.5610),
  TideStation(code: 'DT_0009', name: '영광', latitude: 35.4240, longitude: 126.4130),
  TideStation(code: 'DT_0021', name: '군산', latitude: 35.9729, longitude: 126.5606),
  TideStation(code: 'DT_0022', name: '목포', latitude: 34.7790, longitude: 126.3753),
  TideStation(code: 'DT_0023', name: '위도', latitude: 35.6170, longitude: 126.2980),

  // 남해 (South Coast)
  TideStation(code: 'DT_0031', name: '완도', latitude: 34.3438, longitude: 126.7549),
  TideStation(code: 'DT_0032', name: '제주', latitude: 33.5133, longitude: 126.5244),
  TideStation(code: 'DT_0033', name: '서귀포', latitude: 33.2404, longitude: 126.5630),
  TideStation(code: 'DT_0034', name: '성산포', latitude: 33.4740, longitude: 126.9290),
  TideStation(code: 'DT_0061', name: '여수', latitude: 34.7375, longitude: 127.7620),
  TideStation(code: 'DT_0062', name: '통영', latitude: 34.8361, longitude: 128.4331),
  TideStation(code: 'DT_0063', name: '거제', latitude: 34.8720, longitude: 128.6960),
  TideStation(code: 'DT_0064', name: '마산', latitude: 35.1950, longitude: 128.5760),
  TideStation(code: 'DT_0065', name: '가덕도', latitude: 35.0080, longitude: 128.8220),

  // 동해 (East Coast)
  TideStation(code: 'DT_0041', name: '포항', latitude: 36.0591, longitude: 129.3694),
  TideStation(code: 'DT_0042', name: '울산', latitude: 35.4984, longitude: 129.3840),
  TideStation(code: 'DT_0051', name: '부산', latitude: 35.0961, longitude: 129.0378),
  TideStation(code: 'DT_0081', name: '울진', latitude: 37.0024, longitude: 129.4125),
  TideStation(code: 'DT_0082', name: '후포', latitude: 36.6770, longitude: 129.4550),
  TideStation(code: 'DT_0091', name: '동해', latitude: 37.4958, longitude: 129.1208),
  TideStation(code: 'DT_0092', name: '강릉', latitude: 37.7740, longitude: 128.9460),
  TideStation(code: 'DT_0101', name: '속초', latitude: 38.2076, longitude: 128.5943),
];
