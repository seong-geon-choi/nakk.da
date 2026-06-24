# 광고 수익화 계획 — AppLovin MAX 허브 + AdMob 수요 (낚.다)

> 작성일: 2026-06-16 · 상태: **보류(비공개 테스트 완료 후 착수 예정)**
> 결정: **미디에이션 허브 = AppLovin MAX, 그 안에 AdMob(Google)을 핵심 수요로 등록.**
> 배치/레이아웃 세부는 [`banner-ads-guide.md`](./banner-ads-guide.md) 참조(SDK 무관하게 유효).
>
> 🔄 **2026-06-18 갱신:** 배너 **자리(placeholder)·노출 토글은 이미 앱에 반영**됨(아래 §8-A). 광고 SDK 연동·전면 광고·수익 추정·정책 제약을 §8에 정리(프로덕션 착수 전 그대로 작업). **실제 광고는 아직 미연동.**
>
> 🔄 **2026-06-24 — AppLovin 계정 활성화 게이트 확인:** AppLovin Monetize 가입 시 신규 계정이 **비활성(disabled) 상태로 막힘** — "activation requirements" 미충족(메일/`account-approval@applovin.com` 안내). 원인은 **앱이 아직 비공개(closed) 트랙이라 "라이브 앱" 요건 미달**로 추정. AdMob은 이 게이트가 없으나, AppLovin은 막힘. **결정: 광고사 앱 등록·MAX 연동은 비공개 테스트 종료 후(프로덕션 공개 시점)에 진행**(§0과 동일). 비공개 기간엔 AdMob 계정·결제·세금 인증만 미리 준비. 가입 옵션은 **Monetize**(퍼블리셔)가 맞음(Advertise는 광고주용).

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

---

# 8. 광고 구현 준비안 (2026-06-18 정리 — 프로덕션 착수 전 반영)

> 이번 세션에서 확정/검토한 내용. **SDK 미연동 상태**이며, 프로덕션 수익화 착수 시 §5 + 아래를 함께 구현.

## 8-A. 현재 앱에 반영된 것 (배너 자리 준비 완료)

- **`AdBannerSlot` 위젯**(`lib/core/widgets/ad_banner_slot.dart`): 표준 배너 높이(50dp) 예약 placeholder. 하단 내비게이션 바 인셋만큼 띄워 가림 방지. 현재는 "광고 영역" 표시만(실광고 없음).
- **배치:** 메모목록·통계·지도 화면 **하단**(`Column[Expanded(본문), AdBannerSlot]`).
- **노출 토글:** 설정의 `adsEnabled`(기본 **off**). **개발자 메뉴**(설정 버전 7회 연타 진입)의 "광고 노출" 스위치로 on/off. off면 슬롯이 공간을 차지하지 않음.
- → SDK 연동 시 `AdBannerSlot`의 child를 실제 배너(`MaxAdView`)로 교체하면 됨.

## 8-B. 광고 형식별 배치 방침

| 형식 | 배치 | UI 자리 | 비고 |
|---|---|---|---|
| **배너** | 목록·통계·지도 하단(이미 슬롯) | **필요**(예약됨) | 사용자가 머무는 화면일수록 viewability↑ |
| **전면(Interstitial)** | 목록·지도 **진입 시**(세션당 1회) | **불필요**(SDK 전체화면) | preload 후 트리거에서 `show()` |
| (대안) 앱 오프닝 | 앱 열/복귀 시 | 불필요 | 스플래시에 전면 금지 → 필요시 별도 포맷 |

**광고 금지 화면:** 입력/메모 에디터, 카메라·자(`camera_ruler_screen`), 지도 트래킹/풀스크린, 권한, **스플래시/시작 직후**.

## 8-C. 전면 광고 설계 (착수 시 구현)

- **자리 예약 불필요** — 전면은 SDK가 전체화면을 직접 그림. 배너처럼 placeholder를 두지 않음.
- **흐름:** SDK 초기화 → 전면 **preload(미리 로드)** → 트리거 지점 도달 + 빈도조건 충족 → 준비됐으면 `show()` → 닫힌 뒤 **다음 것 다시 load**.
- **트리거:** 메모 목록 진입 / 지도 진입.
- **★ 세션당 1회(목록·지도 공유):** 두 화면이 **하나의 세션 플래그를 공유** → 그 세션에서 **먼저 도달한 화면에서 1회만** 노출, 이후 다른 화면 진입은 건너뜀. 새 세션에서 리셋.
  - 세션 경계: 간단형(앱 프로세스 수명) 또는 정밀형(마지막 활동 후 30분 타임아웃).
  - 구현: 공유 불리언(예: `interstitialShownThisSession`) + show 직전 게이팅.
- **빈도제한:** 위 1회 캡 + (선택) "오늘/일주일 그만 보기"는 **우리 게이팅**으로 가능(아래 8-D). 단 광고 창 위엔 버튼 못 붙임.

## 8-D. 빈도 제한 / 옵트아웃 옵션

- "오늘 그만 보기 / 일주일간 그만 보기"는 **기능적으로 가능** — `suppressed_until` 시각을 저장하고 `show()` 직전 비교해 건너뜀. 단:
  - **광고 창에는 못 붙임**(크리에이티브 변형 = 정책 위반). 옵션은 **설정 화면 등 광고 밖**에 배치.
  - **무료로 주면 수익 직접 감소.**
- **권장 대안(옵트아웃도 수익화):**
  - **광고 제거 IAP**(결제로 영구/구독 제거) — 표준.
  - **리워드 광고로 임시 제거**(보면 N시간 무광고).

## 8-E. 정책·인정 제약 (반드시 준수)

- **조회가능 노출(viewability):** 픽셀 50%+가 **1초 이상** 표시돼야 인정. **짧은 노출은 수익 인정이 깎임**(vCPM 구매는 1초 미만 0). → 배너는 "머무는 화면"에, 지도처럼 빨리 빠지는 화면은 효과 낮을 수 있음.
- **배너 새로고침 ≥30초**(60초 권장). 더 빠르면 무효 트래픽.
- **무효 트래픽 금지:** 인위적 노출 증대·오클릭 유발 금지. **배너가 하단 내비바 바로 위 → 충분한 간격**으로 오클릭 방지.
- **데이터 보안 양식**(Play Console) 광고 ID 수집 명시 갱신. 해외/EU 대상 시 동의(UMP/CMP).

## 8-F. 수익 추정 (참고 · 가정 기반)

가정: 월 **2세션/사용자**, 배너 **3노출/세션·eCPM $1**, 전면 **1/세션·eCPM $5**(전면 eCPM ≈ 배너 5배). 환율 $1≈₩1,350.

| | 사용자당 월 수익 | 10,000 MAU/월 | 100,000 MAU/월 |
|---|---|---|---|
| 배너만 | ~$0.006 | ~$60 (₩8만) | ~$600 (₩81만) |
| **배너+전면** | ~$0.016 | **~$160 (₩21.6만)** | ~$1,600 (₩216만) |

- 전면 추가 시 **약 2.7배**(중간 가정). **전면이 노출은 적어도 수익 주력**(eCPM 차이).
- 현실 보정: 전면 fill·트리거 100% 아님, 배너 viewability 하향, UX 이탈 리스크 → **하단 범위로 보수적 해석**. 절대액은 **MAU(만 단위~)** 가 좌우.

## 8-G. 프로덕션 착수 체크리스트 (요약)

1. [ ] AppLovin MAX + AdMob 계정·광고단위·미디에이션(§3·§5)
2. [ ] `applovin_max` + Google 어댑터, Manifest AdMob App ID, `main()` 초기화, `ADS_ENV` 분기(§4·§5)
3. [ ] **배너:** `AdBannerSlot` child를 `MaxAdView`로 교체(자리는 이미 있음)
4. [ ] **전면:** preload + 목록·지도 트리거 + **세션 공유 1회 캡** + 닫힘 후 재로드(§8-C)
5. [ ] (선택) 빈도 옵트아웃/광고 제거 IAP/리워드(§8-D)
6. [ ] 정책: viewability·새로고침·오클릭 간격·데이터 보안 양식(§8-E)
7. [ ] 테스트 트랙은 광고 OFF(빈 슬롯)·Mediation Debugger, 프로덕션만 `ADS_ENV=prod`(§4)
