# 광고 수익화 계획 — AppLovin MAX 허브 + AdMob 수요 (낚.다)

> 작성일: 2026-06-16 · 상태: **보류(비공개 테스트 완료 후 착수 예정)**
> 결정: **미디에이션 허브 = AppLovin MAX, 그 안에 AdMob(Google)을 핵심 수요로 등록.**
> 배치/레이아웃 세부는 [`banner-ads-guide.md`](./banner-ads-guide.md) 참조(SDK 무관하게 유효).

---

## 0. 착수 시점

- **현재 상태:** 비공개 테스트(Play `alpha` 트랙, 2.1.1+2019) 검증 중. 광고 작업은 **보류**.
- **착수 트리거:** 비공개 테스트가 일단락되어 기능이 안정됐다고 판단되는 시점.
- 이 문서를 그대로 따라 작업하면 됨.

## 1. 결정 사항과 이유 (요약)

- **허브 = AppLovin MAX**: 무료(미디에이션 수수료 0%), 중립적 실시간 경매, 성숙한 Flutter 플러그인(`applovin_max`), 강한 리포팅/디버깅 도구.
- **AdMob은 버리지 않고 MAX 안의 핵심 수요로 등록**: 비게임 유틸 앱은 AdMob 수요의 fill·eCPM이 가장 강함. MAX가 AdMob을 포함한 여러 네트워크를 경쟁시켜 단가를 최적화하고, 동시에 단일 네트워크 의존도를 분산.
- 자세한 비교 근거는 이 세션 대화 기록 참조(미디에이션 개념, 수수료 0% 구조 등).

## 2. 중요한 선행 이해 (AdMob 직접 연동과의 차이)

| 항목 | AdMob 직접(`google_mobile_ads`) | **AppLovin MAX 허브(이번 방식)** |
|---|---|---|
| 메인 SDK | `google_mobile_ads` | **`applovin_max`** |
| 초기화 | `MobileAds.instance.initialize()` | **`AppLovinMAX.initialize(sdkKey)`** |
| 광고 단위 ID | AdMob 광고 단위 ID 직접 사용 | **MAX 광고 단위 ID** 사용 (AdMob은 MAX 대시보드에서 "네트워크"로 등록) |
| AdMob 계정 | 필요 | **여전히 필요** (어댑터가 AdMob App ID를 요구) |
| 테스트 광고 | Google **공식 테스트 단위 ID** 존재 | **공식 테스트 단위 ID 없음** → 테스트 기기 등록 + Mediation Debugger 사용 |

> 핵심: MAX를 쓰더라도 **AdMob 계정·앱·App ID는 그대로 만들어야 한다**(AdMob 어댑터가 그 App ID로 동작). 다만 앱 코드에서 직접 부르는 ID는 **MAX 광고 단위 ID**다.

## 3. 사전 준비 체크리스트

| 항목 | 내용 |
|---|---|
| AppLovin 계정 | 가입 → 앱 등록 → **SDK Key** 발급, **MAX 광고 단위(배너) ID** 생성 |
| AdMob 계정 | 앱 등록 → **AdMob App ID**, **AdMob 광고 단위 ID** 발급 (MAX에 네트워크로 연결할 때 사용) |
| MAX 대시보드 | Mediation > Manage Networks에서 **Google AdMob 네트워크 활성화** + AdMob 자격증명/광고단위 매핑 |
| 패키지 | `applovin_max` 추가 (현재 광고 의존성 없음, minSdk 26 충족) |
| 어댑터 | **Google(AdMob) 미디에이션 어댑터** 의존성 추가 (Android) |
| Manifest | `<meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" android:value="ca-app-pub-..."/>` **필수** (AdMob 어댑터 요건, 누락 시 크래시) |
| 초기화 | `main()`에서 `await AppLovinMAX.initialize(sdkKey)` |
| 개인정보 | Play Console **데이터 보안 양식** 갱신(광고 ID 수집 명시). 해외/EU 대상이면 동의 흐름(아래 6항) |

## 4. 테스트 / 프로덕션 분리 (계정 정지 방지)

비공개 테스트 빌드도 **release 빌드**라 `kReleaseMode`로 구분 불가 → **명시적 분기** 필요.

- 빌드 시 `--dart-define=ADS_ENV=test` / `=prod` 로 환경 주입.
- **MAX에는 AdMob 같은 공개 테스트 광고 단위 ID가 없다.** 그래서 안전 전략은 둘 중 하나:
  1. **(권장) 테스트 환경에선 광고 비활성/플레이스홀더**: `ADS_ENV=test`면 실제 광고를 안 띄우고 동일 높이의 빈 슬롯만 유지. 통합/레이아웃 검증은 **내 기기에서 Mediation Debugger**로 확인.
  2. **테스트 기기 등록**: `AppLovinMAX.setTestDeviceAdvertisingIds([...])`로 내 기기를 등록하면 그 기기엔 테스트 광고. 단 **테스터 다수의 기기를 모두 등록하기 어려움** → 비공개 테스트 광범위 노출엔 부적합.
- **결론:** 비공개 테스트 트랙엔 **광고를 끄거나 빈 슬롯만** 두고(레이아웃만 검증), 실제 광고는 **프로덕션(`ADS_ENV=prod`)에서만** 켠다. 실광고 자가/테스터 클릭으로 인한 무효 트래픽·정지 위험 원천 차단.

```dart
// 환경 헬퍼 스케치
const adsEnv = String.fromEnvironment('ADS_ENV', defaultValue: 'test');
const adsEnabled = adsEnv == 'prod'; // 프로덕션에서만 실제 광고
```

> 릴리스 워크플로(메모리 `versioning-policy`)의 빌드 명령에 `--dart-define=ADS_ENV=prod`를 프로덕션 출시 시 추가. 비공개 테스트 빌드는 기본값(test) 유지.

## 5. 구현 순서 (착수 시 체크리스트)

1. [ ] AppLovin 계정·앱 등록 → **SDK Key**, **MAX 배너 광고 단위 ID** 발급
2. [ ] AdMob 계정·앱 등록 → **AdMob App ID**, 광고 단위 ID 발급
3. [ ] MAX 대시보드에서 **AdMob 네트워크 활성화** + 광고단위 매핑
4. [ ] `applovin_max` + **Google 어댑터** 의존성 추가, `pub get`
5. [ ] `AndroidManifest.xml`에 AdMob `APPLICATION_ID` meta-data 추가
6. [ ] `main()`에 `AppLovinMAX.initialize(sdkKey)` 추가 + `ADS_ENV` 분기 헬퍼
7. [ ] 공통 배너 위젯 작성(높이 예약 포함 — 레이아웃 흔들림 방지, [`banner-ads-guide.md`](./banner-ads-guide.md) §1·§5 원리 동일)
8. [ ] 광고 위치 삽입 (아래 7항)
9. [ ] 내 기기에서 **Mediation Debugger**로 어댑터/연결 확인
10. [ ] 데이터 보안 양식 갱신
11. [ ] 비공개 테스트: 광고 OFF(빈 슬롯)로 레이아웃만 검증
12. [ ] 프로덕션 출시 빌드에서만 `ADS_ENV=prod`로 실제 광고 ON

### `applovin_max` 배너 위젯 스케치
```dart
// 초기화 (main)
await AppLovinMAX.initialize('YOUR_SDK_KEY');

// 배너 위젯 — MaxAdView 사용, 높이는 예약 슬롯에 넣어 흔들림 방지
MaxAdView(
  adUnitId: 'YOUR_MAX_BANNER_AD_UNIT_ID',
  adFormat: AdFormat.banner,
  listener: AdViewAdListener(
    onAdLoadedCallback: (ad) {},
    onAdLoadFailedCallback: (adUnitId, error) {},
  ),
);
```

## 6. UX·정책 결정 사항 (착수 전 확정)

- **노출 범위:** 어느 화면까지? (아래 7항 제안 기준)
- **광고 제거 인앱결제** 제공 여부.
- **동의 흐름:** 해외/EU 대상이면 동의 관리(예: Google UMP 또는 MAX 연동 CMP). AppLovin은 사용자 동의 플래그(`setHasUserConsent` 등) 전달 필요.

## 7. 광고 위치 계획 (이 앱 기준 — 이번 세션 합의)

핵심 작업 흐름(입력·촬영·기록)은 건드리지 않고 **목록/조회성 화면**에만 배치.

| 화면 | 추천 | 비고 |
|---|---|---|
| `file_list_screen` (날짜 목록) | 하단 배너 | 1차 적용 |
| `stats_screen` (통계) | 하단 배너 | 1차 적용 |
| `search_screen` (검색 결과) | 결과 하단 배너 | 2차 |
| 홈/메모 `_ActionBar` 위 | 배너 슬롯 | [`banner-ads-guide.md`](./banner-ads-guide.md) §2 배치 그대로 (FAB 겹침 주의) |
| 화면 전환 시 | 전면(interstitial) + 빈도 제한 | 반응 보고 신중히, 후순위 |

**광고 금지 화면:** 카메라/자(`camera_ruler_screen`), 메모 에디터(입력 중), 지도 트래킹/풀스크린, 권한 화면.

**1차 권장:** `file_list` + `stats` 하단 배너만 먼저. 전면 광고는 이후 판단.

---

## 부록: 대안 (참고)

- **더 단순하게 가려면** AdMob 직접 연동(`google_mobile_ads`)이 가장 쉬움 → 그 경우 [`banner-ads-guide.md`](./banner-ads-guide.md)를 그대로 따르면 됨(공식 테스트 단위 ID 사용 가능). MAX 허브는 "추가 비용 0으로 수익 최적화 + 의존도 분산"이 목적.
- Unity LevelPlay는 게임 수요 편중이라 이 앱엔 후순위.
