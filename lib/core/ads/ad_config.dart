/// 광고 환경 분기와 광고 단위 ID.
///
/// 비공개 테스트 빌드도 release 빌드라 `kReleaseMode`로 구분 불가 → 명시적 분기.
/// 프로덕션 출시 빌드에만 `--dart-define=ADS_ENV=prod`를 주입한다.
/// 그 외(테스트/개발)에는 Google 공식 테스트 광고 ID를 써서 실클릭 위험을 없앤다.
library;

const String _adsEnv = String.fromEnvironment('ADS_ENV', defaultValue: 'test');

/// 프로덕션(실광고) 여부. `--dart-define=ADS_ENV=prod`일 때만 true.
bool get adsIsProd => _adsEnv == 'prod';

/// 배너 광고 단위 ID.
/// - test: Google 공식 테스트 배너 단위 ID(항상 테스트 광고 → 정지 위험 0)
/// - prod: 실제 AdMob 배너 단위 ID
String get bannerAdUnitId => adsIsProd
    ? 'ca-app-pub-5653160308014888/4615860409'
    : 'ca-app-pub-3940256099942544/6300978111';
