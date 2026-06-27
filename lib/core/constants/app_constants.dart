class AppConstants {
  static const String dateFormat = 'yyyy-MM-dd';
  static const String timeFormat = 'HH:mm';
  static const String fileNamePattern = r'^\d{4}-\d{2}-\d{2}\.md$';
  static const String photosDirName = 'photos';
  static const int gpsTimeoutSeconds = 5;
  static const String defaultSavePathKey = 'save_path';
  static const String showLocationButtonKey = 'show_location_button';
}

/// 어종 입력 드롭다운에 표시할 자주 잡는 어종 목록 (자유 입력도 가능)
const List<String> kCommonFishSpecies = [
  '감성돔', '참돔', '돌돔', '벵에돔', '볼락', '우럭', '광어', '농어', '민어',
  '망상어', '학공치', '숭어', '전갱이', '고등어', '갈치', '삼치', '붕장어',
  '부시리', '방어', '도다리', '가자미', '노래미', '쥐노래미',
  '무늬오징어', '갑오징어', '한치', '주꾸미', '문어',
  '배스', '붕어', '잉어', '송어', '쏘가리', '가물치', '메기', '민물장어',
];
