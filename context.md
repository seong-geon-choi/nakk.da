# context.md — vo-rec 개발 이력

**최종 업데이트:** 2026-06-12 (세션 E)

---

## 세션 이력 요약

### 세션 E (2026-06-12): 기능 검토 + 어종/마릿수 기록 추가

#### 0. 기능 검토 리포트
- `docs/feature-review.md` 작성: 추가/개선 기능 우선순위 정리
- 로드맵: ① 어종/마릿수 필드 → ② 검색/필터 → ③ 통계 대시보드 (어종 필드 공유)

#### 1. 어종/마릿수 구조화 필드 추가 (로드맵 ①)
- `MemoEntry`에 `fishSpecies`(String?), `fishCount`(int?) 추가
- `.md` 포맷: `- 🐟 {어종} {N}마리` 줄 (어종만/마릿수만도 지원). 구 포맷 하위호환 (줄 없으면 null)
- `md_serializer.dart`: serializeEntry 직렬화 + parseBlocks 파싱 (`📏` 길이 줄과 동일 위치)
- `memo_input_sheet.dart`: `_buildCatchSection()` — 어종(자유입력 TextField + PopupMenu 드롭다운) + 마릿수 + 길이
  - 공통 어종 목록: `app_constants.dart` `kCommonFishSpecies`
  - `_save()` 가드에 조과 정보 추가 → 어종/마릿수/길이만 있어도 저장됨 (기존엔 텍스트/미디어 없으면 폐기)
- `memo_entry_card.dart`: `_catchLabel()` — `🐟 감성돔 · 2마리 · 📏 38.5cm` 한 줄 표시
- 테스트: `md_serializer_test.dart`에 조과 직렬화/파싱/왕복/하위호환 9개 추가 (통과)
- 위젯 테스트 `memo_input_sheet_test.dart` 라인 123: `findsOneWidget` → `findsWidgets` (stale 단언 수정, TextField 다수 존재)

#### 2. 이동 현황 라벨 "장소"로 통일
- 코드 출력은 `## 현황 (HH:mm 장소)` 유지
- 테스트(`md_serializer_test.dart`)·문서(README/dev-plan/architecture/prd/tasks) "이동" → "장소"
- 파서는 시각만 추출 → 레거시 "이동" 파일도 계속 정상 파싱 (파싱 테스트 1건은 "이동" 입력 유지로 하위호환 검증)

#### 3. 메모 검색/필터 (로드맵 ②)
- 신규 `features/search/`:
  - `data/search_service.dart` — 전체 .md 파싱 → `SearchHit`(date/filePath/entry/address) 평탄화. 파일 대표 주소는 첫 `- 📍` (GPS 좌표만이면 제외)
  - `domain/models/search_hit.dart`, `presentation/search_provider.dart`(autoDispose FutureProvider), `presentation/search_screen.dart`
- 검색 대상: 메모 텍스트 + 어종 + 장소(주소). 필터: 어종 칩(데이터 내 빈도순), 날짜 범위
- 전체 1회 로드 후 메모리 필터링 (디바운스 없음). 결과는 날짜별 헤더 + `MemoEntryCard` 재사용, 탭 시 해당 날짜 파일로 이동
- 진입점: 메모 목록(`FileListScreen`) AppBar 검색 아이콘 → `AppRoutes.search`
- 라우터: `AppRoutes.search='/search'` + GoRoute 추가

#### 4. 조과 통계 대시보드 (로드맵 ③)
- 신규 `features/stats/`:
  - `domain/models/catch_stats.dart` — `CatchStats.from(hits)` 순수 집계 (기록일/총마릿수/어종별/월별)
    - 마릿수 = `fishCount ?? 1`(조과 정보 있으면 1). 어종 없이 길이/마릿수만 → `(어종 미상)`
  - `presentation/stats_screen.dart` — 기간(전체/올해/이번달) + 요약카드 + 어종별 표(최대 길이 PB) + 월별 막대(경량, 차트 라이브러리 미사용)
- 데이터는 `searchHitsProvider`(검색용 전체 로드) 재사용
- 진입점: 메모 목록 AppBar 통계 아이콘 → `AppRoutes.stats='/stats'`
- 테스트: `catch_stats_test.dart` 8개 (집계/PB/미상/월별 등) 통과

#### 4-1. 메모 텍스트에서 어종·길이 자동 인식
- `core/utils/species_detector.dart`:
  - `detectFishSpecies(text)` — `kCommonFishSpecies` 중 가장 먼저 등장(동일 위치 시 더 긴 이름). 쥐노래미 > 노래미
  - `detectFishLength(text)` — cm·㎝·센티미터·센티·센치·짜리 단위 숫자 추출, 1~300cm 범위만, 가장 먼저 등장
- 적용: ① 입력 시트 `_textCtrl` 리스너 `_autoDetectFromText`로 어종·길이 필드가 **빈 경우에만** 라이브 자동 채움(수동 입력/AR 측정값 미침범)
  ② `_save()` 저장 안전망(어종·길이 각각) ③ `home_screen._saveVoiceDirectly`(음성 즉시 저장)
- 테스트: `species_detector_test.dart` 11개 통과(어종 5 + 길이 6)

#### 5. 기존 stale 테스트 정리 (이번 작업과 무관했던 실패 10건 → 0건)
- `settings_screen_test.dart` 6건: 하위 화면 구조/문구 변경 반영 (진입 후 검증)
- `photo_service_test.dart`·`photo_service_impl_test.dart`: `PhotoSource`에 `arCamera` 추가 반영 (length 3, gallery index 2)
- `settings_repository_impl_test.dart`: mock에 `photo_save_path` 추가(path_provider 회피) + savePath 키명 `save_path`→`save_saf_uri` 정정
- **코드 버그 수정**: `file_list_repository_impl.dart` `_countEntries`가 `'### '` 부분문자열로 세어 `#### ` 하위헤더까지 카운트 → `RegExp(r'^### ', multiLine: true)`로 정정

#### 10. 카메라 화면 세로 고정 + 컨트롤만 회전
- 문제: OS 자동회전으로 카메라 레이아웃 전체가 돌아 촬영 버튼 위치가 바뀜
- 해결: `camera_ruler_screen` 진입 시 `SystemChrome.setPreferredOrientations([portraitUp])`로 레이아웃 고정,
  이탈 시 `DeviceOrientation.values`로 복구
- 기기 방향 감지: `sensors_plus`(신규 의존성) accelerometer로 `_uiQuarterTurns`(0/1/3) 계산
  (ay 우세 → 세로 0, 아니면 ax 부호로 가로 1/3, 평평하면 보류)
- 컨트롤(뒤로/해상도/워터마크/모드탭/REC/토스트)을 `_rot()`(`AnimatedRotation`)로 감싸 제자리 회전
- **워터마크 박스도 회전**: `_WatermarkOverlay`에 `quarterTurns` 전달 → 박스를 `AnimatedRotation`으로 제자리 회전
- **AR 카메라 워터마크 박스 회전**: `OrientationEventListener`로 기기 방향 감지 → `wmOverlay.rotation` 설정.
  보정식 `target = (disp - device)`로 윈도우가 이미 회전하면 net≈0(이중 회전 방지), 고정이면 보정
- ⚠️ 가로 회전 방향(부호)은 기기 검증 필요 — 반대면 일반: `_onAccel`의 `1 : 3` 스왑 / AR: `(disp - device)` ↔ `(device - disp)`

#### 9. 워터마크 자유 위치(플로팅) + 날짜 포맷 2종 추가
- `WatermarkSettings`에 `posX`/`posY`(0~1) 추가. 구 `position` enum은 마이그레이션용으로 유지
  (fromJson: posX/posY 없으면 `posFromCorner(position)`에서 유도). toJson/copyWith 반영
- 실제 굽기 `watermark.dart` `_boxOffset(posX,posY,...)` — `margin + pos*free`로 자유 배치
- **카메라 화면에서 워터마크 박스를 드래그**해 위치 이동(`_WatermarkOverlay`에 `onMove` 콜백).
  - 처음엔 delta 누적 방식이라 손가락보다 느려 여러 번 끌어야 했음 → **손가락 절대 위치**(영역 `_areaKey`로 global→local 변환, `local/avail`)로 변경해 1:1 즉시 추종
  - 드래그 중 로컬 `_dragX/_dragY`로 즉시 반영, panEnd에 1회만 settings 저장
  - 드래그는 박스 위에서 시작 → 카메라 포커스/줌 제스처와 분리. 옅은 테두리로 표시
- 설정 미리보기도 동일(절대 위치) 드래그. 4코너 버튼은 빠른 프리셋으로 유지
- **AR 카메라(네이티브)에도 동일 구현**:
  - `ArMeasureActivity`: wmOverlay에 OnTouchListener로 드래그(절대 margin), `wmPosX/wmPosY` 갱신.
    코너 gravity 제거 → `positionWatermark()`로 posX/posY 비율 배치. 드래그 중엔 재배치 skip(`wmDragging`)
  - 결과 전파: ArMeasureActivity setResult(EXTRA_POS_X/Y) → MainActivity onActivityResult가 map에 posX/posY 추가
    → ar_service 결과 레코드(posX/posY) → memo_input_sheet가 settings에 반영 + applyWatermark에 사용
  - launch 시 ar_service가 wmPosX/wmPosY 전달 → AR 시작 위치도 설정과 일치
- Kotlin AR 라이브 프리뷰: ar_service에서 posX/posY를 **가장 가까운 코너**로 변환해 전달(네이티브 레이아웃 무수정)
- 날짜 포맷 추가: `yyyy-MM-dd HH:mm:ss`(연-월-일 시:분:초), `yyyy-MM-dd HH:mm`(연-월-일 시:분)
  → watermark.dart/_미리보기/_카메라/_Kotlin AR `when` 모두 케이스 추가
- 테스트: `app_settings_test.dart`에 posX/posY 기본값·왕복·구설정 마이그레이션 5개 추가

#### 7. 마릿수 제거 — "사진/메모 1건 = 1마리"
- `MemoEntry.fishCount` 필드 제거. 입력 시트 마릿수 칸 제거
- `md_serializer`: 직렬화 `- 🐟 {어종}`만. 파싱은 구 포맷 `N마리` 접미사를 무시(어종만 추출)
- `CatchStats.from`: 엔트리당 1마리 집계(`+1`)
- `memo_entry_card._catchLabel`: 어종·길이만 표시

#### 8. 어종 목록 사용자 관리 + 신규 어종 자동 추가
- `AppSettings.fishSpecies`(List<String>, 기본 `kCommonFishSpecies`) 추가, prefs `fish_species`로 영속화(`getStringList`/`setStringList`)
- `SettingsNotifier.addFishSpecies/removeFishSpecies`
- 설정: '어종 목록 관리' 하위 화면(`_FishSpeciesSubScreen`) — 추가 입력 + 삭제
- 입력 시트: 드롭다운/자동탐지에 사용자 목록 사용, 저장 시 직접 입력한 신규 어종을 `addFishSpecies`로 자동 등록
- `detectFishSpecies(text, [species])` — 목록 인자 추가(기본 kCommonFishSpecies)
- 테스트: settings_repo fishSpecies 왕복, detector 사용자목록 케이스 추가
- settings_screen_test: 어종 항목 추가로 목록이 길어져 '권한 설정' 탭 hit-test 실패 → `setSurfaceSize(1080x3000)`로 큰 화면 고정 후 직접 탭

#### 6. 트래킹 버튼 깜빡임 수정
- 원인: `todayFileProvider`/`dayFileProvider` `build()`가 `ref.watch(settingsProvider.future)`로
  설정 객체 전체를 구독 → `locationTrackingEnabled` 한 필드만 바뀌어도 재빌드되어
  `AsyncLoading` → 홈 본문 `when(loading: 스피너)`가 잠깐 떠 깜빡임
- 수정: `ref.watch(settingsProvider.selectAsync((s) => s.savePath))`로 savePath만 구독
  → 트래킹 토글 등 무관한 설정 변경에는 재로딩하지 않음

#### UI 문구 변경
- 메인 FAB: `현재 위치 정보 추가` → `환경 추가`
- 설정 토글: `환경 정보 추가 버튼 표시`

#### 테스트 현황
- `flutter analyze lib`: 변경/신규 파일 이슈 없음 (md_serializer:391 기존 lint도 보간으로 해소)
- `flutter test`: **150개 전부 통과**
- 기기 빌드/설치: `flutter build apk --debug --no-tree-shake-icons` → `adb install -r` 정상

### 세션 A (이전): 백업 시스템 구현 + 트래킹 버그 조사

#### 주요 구현
- **Google Drive 백업/복원** (`backup_provider.dart`, `drive_backup_service.dart`)
  - 로컬 매니페스트(SharedPreferences `backup_md_manifest`) 기반 스킵 로직
    - Drive API `size` 반환 null 문제로 manifest 방식으로 전환
    - manifest: `{filename: utf8_byte_length}` 업로드 성공 시에만 갱신
  - Drive 파일 ID 사전 조회 → `_findFile` API 호출 제거
  - 병렬 업로드/복원 (4개씩 `Future.wait`)
  - 미디어 파일 백업 및 복원 (SAF `writePhotoBytes` Kotlin 핸들러 추가)
  - 진행률 인라인 표시 (`LinearProgressIndicator` in ListTile subtitle)
  - 결과: 스낵바 출력 (백업·복원 공통)
- **화면 깜빡임 수정**: `_updateSyncStatus`에서 `ref.invalidateSelf()` 제거, `skipLoadingOnReload: true` 추가
- **복원 최적화**: manifest 기반 다운로드 스킵, 내용 동일하면 쓰기 생략 (`merged == localContent`)
- **진행률 표시 수정**: `total = mdFiles.length + driveMediaFiles.length`

#### 트래킹 데이터 조사 (진행 중 → 다음 세션에서 완료)
- `appendTrackPoints/replaceBlock/removeBlock`: 모두 trackPoints 정상 보존
- **발견된 버그 2개**는 다음 세션에서 수정

---

### 세션 B (현재): 트래킹 버그 수정 + 갤러리/권한 개선

#### 1. 트래킹 데이터 유실 버그 2개 수정

**버그 1 — `_mergeContent` trackPoints 누락** (`backup_provider.dart:331`)
- 복원 시 `buildFullContent(date, sorted)` 호출에 trackPoints 인자 누락
- 복원 실행 시 해당 날짜의 모든 트래킹 데이터가 지워지는 치명적 버그
- 수정: 로컬/드라이브 양쪽 trackPoints를 파싱 후 타임스탬프 기준으로 병합하여 전달

**버그 2 — SharedPreferences 경쟁 조건** (`LocationTrackingService.kt`, `MainActivity.kt`)
- `savePoint()`(GPS 콜백 스레드)와 `getAndClearTrackPoints`(메인 스레드)가
  같은 키에 대해 동기화 없이 읽기→수정→쓰기 수행
- 타이밍이 겹치면 GPS 포인트 1~2개 유실 가능
- 수정: `companion object { @JvmField val pendingLock = Any() }` 추가,
  양쪽 모두 `synchronized(pendingLock)` + `apply()` → `commit()` 변경

#### 2. 갤러리 인터페이스 — 권한 문제 해결

**문제**: `PermissionState.limited`(부분 접근) 상태에서 최근 촬영 사진이 표시되지 않음

**시도 1 (철회)**: `image_picker().pickMedia()` 시스템 피커로 전환
- 미리보기 불가, 탭 선택 UI 부재로 사용성 문제 → 롤백

**최종 방향**: `photo_manager` 기반 커스텀 갤러리 유지 + 권한 처리 개선
- `PermissionState.limited` → denied와 동일하게 처리 (설정 안내 화면)
- 갤러리 화면에서 권한 부족 시 `Permission.photos.request()` + `Permission.videos.request()` 직접 호출
  → Android 13/14에서 limited 상태에도 "모두 허용" 시스템 다이얼로그 재표시
- "권한 허용하기" 버튼 → 시스템 다이얼로그 재요청 / "설정에서 변경" → openAppSettings() 폴백

#### 3. Permission.videos 추가 (전체 갤러리 접근 필수 조건)

Android 13+ 에서 `photo_manager`가 `authorized` 상태가 되려면 `READ_MEDIA_IMAGES` + `READ_MEDIA_VIDEO` 모두 필요.
기존에 `Permission.photos`(이미지)만 요청하고 있었음.

변경 파일:
- `permission_service_impl.dart`: `Permission.videos` → `_required` 추가
- `permission_screen.dart`: "사진/동영상" 항목으로 통합 표시 (내부에서 둘 다 요청)
- `settings_screen.dart`: 권한 설정 화면에 "동영상" 항목 추가

#### 4. 빌드 플래그
- `--no-tree-shake-icons` 필수 (`photo_manager` 제거 후 재추가 과정에서 아이콘 99% 제거 현상 발견)

---

### 세션 D (2026-06-11): 패키지명 변경 + 동영상 저장 통일

#### 1. 패키지명 변경

`com.nakkda.nakkda` → `com.sgchoisg.nakkda`

변경 파일 (20개):
- `android/app/build.gradle.kts`: `namespace`, `applicationId`
- Kotlin 11개 파일: `package` 선언, MethodChannel명, BroadcastAction 상수
- Dart 7개 파일: MethodChannel명
- `README.md`, `docs/architecture.md`: 경로 예시

Play Console: 비공개 테스트 중이었으므로 새 앱으로 재등록 필요.
Google Cloud Console OAuth 클라이언트도 패키지명 업데이트 필요.

#### 2. 동영상 저장 경로 통일 (사진과 동일하게)

**문제**: 동영상이 앱 전용 외부 저장소(`Android/data/패키지명/files/videos/`)에 저장됨
→ 앱 삭제 시 파일 소멸, 패키지명 변경 시 경로 깨짐

**수정**:
- `MainActivity.kt` `saveToGallery`: 동영상(mp4/mov/3gp/mkv) 감지 시 `MediaStore.Video.Media`로 분기
  - 동영상은 `content://media/external/video/media/ID` URI 반환 (파일 경로 대신)
  - 이유: ExoPlayer가 `file://` 경로로 MediaStore 동영상에 직접 접근 불가 (`Source error`)
- `camera_ruler_screen.dart` `_saveVideo`: 앱 전용 복사 로직 제거 → `saveToGallery` 단일 호출
- `memo_input_sheet.dart` `copyGalleryVideo`: `saveToGallery` 래퍼로 교체

**결과**: 카메라/갤러리 동영상 모두 `DCIM/nakkda/`에 저장, `.md`에 `content://` URI 기록

#### 3. 동영상 플레이어 수정

**버그**: `VideoPlayerController.file(File(path))`로 MediaStore 동영상 재생 시 로딩에서 멈춤

**수정** (`video_player_widget.dart`):
- `content://`로 시작하는 경로 → `VideoPlayerController.contentUri(Uri.parse(path))`
- `_resolve`: `content://` URI는 savePath와 합치지 않고 그대로 반환

---

### 세션 C (2026-06-11): 갤러리 대폭 개선 + v1.2.7

#### 1. 갤러리 권한 루트 원인 수정

`AndroidManifest.xml`에서 `READ_MEDIA_VISUAL_USER_SELECTED` 제거.
- 이 권한이 선언되어 있으면 Android 14+에서 사진 선택 다이얼로그에 "선택한 사진만 허용" (partial/limited) 옵션이 추가됨
- 사용자가 partial 허용 시 `PermissionState.limited` → 최초 선택 사진 외 최근 촬영 사진 미표시
- 제거 후 "모두 허용" / "거부" 2가지만 표시 → 루트 원인 제거

#### 2. 갤러리 정렬 수정

`FilterOptionGroup(orders: [OrderOption(createDate, asc: false)])` 명시 추가.
- Samsung One UI에서 기본 정렬이 날짜 오름차순으로 동작하여 오래된 사진만 표시되던 문제 해결
- `size: 500` 고정에서 무한 스크롤로 변경

#### 3. 갤러리 기능 추가

`gallery_picker_screen.dart` 전면 개편:

| 기능 | 구현 |
|------|------|
| 날짜별 그룹 헤더 | `_buildGroups()` — 오늘/어제/YYYY년 M월 D일 |
| 무한 스크롤 | `_onScroll()` — 하단 400px 전 다음 80개 로드 |
| 우측 드래그 스크롤바 | `Scrollbar(interactive: true, thumbVisibility: true)` |
| 탭 미디어 수량 표시 | `_loadCounts()` — 각 탭 비동기 카운트 로드 |
| 다중 선택 + 삭제 | 길게 누르기 → 선택 모드 → AppBar 삭제 버튼 → 확인 다이얼로그 → `PhotoManager.editor.deleteWithIds` |

#### 4. 버전 업

`pubspec.yaml`: `1.2.6+2012` → `1.2.7+2013`

---

## 현재 상태

### 구현 완료 기능

| 기능 | 상태 |
|------|------|
| 음성 메모 (볼륨 버튼 트리거) | ✅ |
| 텍스트/사진/동영상 메모 | ✅ |
| GPS 역지오코딩 + 기상/물때/수온 | ✅ |
| 날짜별 .md 파일 저장 (SAF) | ✅ |
| 파일 목록/뷰어/편집/삭제 | ✅ |
| 지도 (GPS 핀 + 경로 클러스터링) | ✅ |
| AR 길이 측정 | ✅ |
| 이동 경로 기록 (LocationTrackingService) | ✅ |
| Google Drive 백업/복원 | ✅ |
| 갤러리 (날짜 그룹, 무한 스크롤, 삭제) | ✅ |
| 날짜별 사진 일괄 추가 | ✅ |
| 어종/마릿수 기록 (메모 엔트리) | ✅ |

### 주요 파일 경로

| 파일 | 역할 |
|------|------|
| `lib/features/backup/presentation/backup_provider.dart` | 백업/복원 핵심 로직 |
| `lib/features/backup/data/drive_backup_service.dart` | Google Drive API 래퍼 |
| `lib/core/screens/gallery_picker_screen.dart` | 커스텀 갤러리 (photo_manager) |
| `lib/features/permission/data/permission_service_impl.dart` | 권한 목록 (photos + videos) |
| `android/.../LocationTrackingService.kt` | GPS 트래킹 포그라운드 서비스 |
| `android/.../MainActivity.kt` | 메서드 채널 핸들러 |

### 알려진 미해결 이슈

없음 (현재 기준)

---

## 기술 결정 사항

| 항목 | 결정 | 이유 |
|------|------|------|
| 백업 스킵 로직 | 로컬 manifest (SharedPreferences) | Drive API `size` 필드가 일부 파일에서 null 반환 |
| 병렬 처리 배치 크기 | 4 | Drive API 과부하 방지와 속도 균형 |
| 갤러리 인터페이스 | `photo_manager` 커스텀 | 시스템 피커는 미리보기 불가 |
| 아이콘 트리쉐이킹 | `--no-tree-shake-icons` 비활성화 | 패키지 변동 시 아이콘 대규모 누락 현상 |
| 트래킹 SharedPrefs 동기화 | `synchronized` + `commit()` | `apply()` 비동기 간 경쟁 조건 방지 |
| 사진/동영상 권한 | `Permission.photos` + `Permission.videos` | Android 13+ photo_manager authorized 조건 |
| 패키지명 | `com.sgchoisg.nakkda` | `com.nakkda.nakkda`는 중복, 개발자 식별자로 통일 |
| 동영상 저장/재생 | `MediaStore.Video.Media` + content URI | ExoPlayer가 file:// 경로로 MediaStore 파일 접근 불가 |
