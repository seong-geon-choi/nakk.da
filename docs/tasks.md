# tasks.md: vo-rec 개발 Task 목록

**버전:** 1.0
**작성일:** 2026-06-02
**범위:** Phase 1 MVP

---

## 1. Epic 목록

| Epic ID | Epic 이름 | Phase | 비고 |
|---------|----------|-------|------|
| PERM | 권한 관리 | Phase 1 MVP | 앱 진입 시 마이크·위치·카메라·저장소 권한 요청 |
| MEMO | 메모 작성 및 저장 | Phase 1 MVP | 텍스트·음성·사진 메모 작성 및 .md 파일 저장 |
| LOCATION | 현황 블록 (위치 이동) | Phase 1 MVP | GPS 좌표 기반 현황 블록 추가 |
| FILE | 파일 목록 및 관리 | Phase 1 MVP | 파일 목록 조회·뷰어·이름 변경·삭제 |
| SETTINGS | 앱 설정 | Phase 1 MVP | 저장 경로·버튼 표시·권한 상태 관리 |
| CORE | 앱 기반 구조 | Phase 1 MVP | 프로젝트 초기화·라우팅·테마·공통 컴포넌트 |
| — | GPS 역지오코딩 | Phase 2 | 좌표 → 시/군/면 주소 자동 변환 |
| — | 기상청 단기예보 API | Phase 2 | 기온 자동 입력 |
| — | 해양조사원 API (물때·수온) | Phase 2 | 물때·수온 자동 입력 |
| — | 조위관측소 최근접 계산 | Phase 2 | GPS 거리 기반 관측소 선택 |
| — | 볼륨 버튼 트리거 | Phase 3 | 화면 꺼진 상태에서 볼륨↑ 2회로 녹음 시작 |
| — | 지도 보기 | Phase 4 | 메모·사진 위치 핀 표시 |
| — | 물고기 길이 측정 / 어종 인식 | Phase 5 | 사진 기반 ML 기능 |

---

## 2. Epic별 Story 분해

---

### CORE — 앱 기반 구조

#### CORE-001: Flutter 프로젝트 초기화 및 패키지 설정

**설명:** Flutter 프로젝트를 생성하고 pubspec.yaml에 필요한 패키지를 추가한다. Android 최소 SDK를 26으로 설정하고 기본 폴더 구조(feature-first)를 잡는다.

**인수 조건:**
- `flutter create` 로 프로젝트 생성 완료
- pubspec.yaml에 flutter_riverpod, go_router, speech_to_text, image_picker, geolocator, permission_handler, path_provider, shared_preferences 추가
- android/app/build.gradle의 minSdkVersion = 26 설정
- `lib/` 하위에 core/, features/, home/ 폴더 구조 생성

**우선순위:** P0

---

#### CORE-002: 앱 진입점, 라우팅 및 다크 테마 설정

**설명:** main.dart에 ProviderScope를 설정하고, app.dart에서 MaterialApp.router와 GoRouter를 초기화한다. 다크 테마를 기본값으로 적용한다.

**인수 조건:**
- main.dart에서 ProviderScope로 앱을 래핑
- go_router로 SCR-01~06 라우트 정의
- 다크 테마 기본 적용 (app_theme.dart)
- 앱 Cold start 3초 이내

**우선순위:** P0

---

#### CORE-003: 공통 유틸 및 공통 컴포넌트 구현

**설명:** 날짜 포맷, 파일명 파싱 유틸과 ActionButton, MemoEntryCard, LocationStatusCard, PermissionStatusChip, ConfirmDialog, EmptyStateView 공통 컴포넌트를 구현한다.

**인수 조건:**
- date_formatter.dart: YYYY-MM-DD, HH:mm, 상대 날짜("오늘"/"어제"/"N일 전") 포맷 지원
- file_name_parser.dart: YYYY-MM-DD.md 패턴 파싱
- ActionButton: 최소 탭 영역 72×72dp, 아이콘 32dp, 레이블 12sp
- MemoEntryCard: photoPath 있으면 이미지, 없으면 텍스트 렌더링
- LocationStatusCard: null 필드는 `-` 플레이스홀더 표시
- ConfirmDialog: isDestructive 시 확인 버튼 빨간색, extra 위젯 슬롯 지원
- EmptyStateView: 메시지/보조메시지 중앙 정렬

**우선순위:** P0

---

### PERM — 권한 관리

#### PERM-001: 권한 요청 화면 구현 (SCR-01)

**설명:** 앱 최초 실행 시 마이크·위치·카메라·저장소 권한을 안내 문구와 함께 순차 요청하는 화면을 구현한다.

**인수 조건:**
- 4가지 권한 카드(아이콘 36dp + 설명 텍스트) 표시
- "권한 허용하기" 버튼 탭 시 마이크 → 위치 → 카메라 → 저장소 순서로 OS 팝업 호출
- 권한 거부 시에도 앱 진행 차단 없이 다음 권한으로 이동
- "나중에 하기" 탭 시 SCR-02로 이동
- 모든 권한 처리 완료 후 SCR-02로 자동 이동

**우선순위:** P0

---

#### PERM-002: 권한 상태 Provider 및 PermissionGate 구현

**설명:** PermissionService 인터페이스와 permission_handler 구현체를 작성하고, PermissionGate 위젯이 앱 진입 시 권한 상태를 체크하여 SCR-01 또는 SCR-02로 분기한다.

**인수 조건:**
- PermissionService: 권한 상태 조회 및 요청 메서드 정의
- PermissionServiceImpl: permission_handler 패키지로 구현
- permissionProvider: 각 권한별 PermissionStatus를 Riverpod 상태로 관리
- PermissionGate: 미허용 권한 1개 이상 시 SCR-01 진입, 모두 허용 시 SCR-02 진입

**우선순위:** P0

---

### SETTINGS — 앱 설정

#### SETTINGS-001: 설정 도메인 및 데이터 레이어 구현

**설명:** AppSettings 모델, SettingsRepository 인터페이스, shared_preferences 기반 구현체를 작성한다.

**인수 조건:**
- AppSettings: savePath(String), showLocationButton(bool) 필드
- SettingsRepository: read/write 인터페이스
- SettingsRepositoryImpl: shared_preferences로 영속 저장
- settingsProvider: 앱 재시작 후에도 값 유지 확인
- savePath 기본값: path_provider의 getExternalStorageDirectory()

**우선순위:** P0

---

#### SETTINGS-002: 설정 화면 구현 (SCR-06)

**설명:** 저장 경로 변경, 위치 추가 버튼 표시 토글, 권한 상태 확인 및 OS 설정 이동을 제공하는 설정 화면을 구현한다.

**인수 조건:**
- 저장 경로 항목 탭 시 경로 변경 다이얼로그 표시 (기존 파일 이동 없음 안내 포함)
- 위치 추가 버튼 SwitchListTile 토글 즉시 저장
- 권한 4가지 항목에 PermissionStatusChip(허용 초록/거부 빨강) 표시
- 거부 권한 탭 시 OS 앱 설정 화면으로 이동 (openAppSettings)

**우선순위:** P0

---

### MEMO — 메모 작성 및 저장

#### MEMO-001: .md 파일 직렬화/파싱 구현

**설명:** md_serializer.dart에서 MemoEntry와 LocationStatus를 .md 형식으로 읽고 쓰는 순수 Dart 로직을 구현한다.

**인수 조건:**
- 쓰기: `### HH:mm | 🛰 lat, lng\n텍스트` 형식으로 append
- 쓰기: GPS 없으면 `### HH:mm` 형식(좌표 생략)
- 쓰기: 사진 메모는 `![](photos/YYYY-MM-DD_HH-mm-ss.jpg)` 삽입
- 읽기: `---` 구분자 블록 분리 → MemoEntry 파싱
- 읽기: `## 현황` 블록 → LocationStatus 파싱
- 파일 최초 생성 시 `# YYYY-MM-DD` 헤더 삽입

**우선순위:** P0

---

#### MEMO-002: 메모 Repository 및 Provider 구현

**설명:** MemoRepository 인터페이스와 파일 I/O 구현체, memoProvider를 작성한다.

**인수 조건:**
- MemoRepository: appendEntry(date, MemoEntry), loadDayFile(date) 메서드
- MemoRepositoryImpl: 파일 없으면 헤더 생성 후 append
- memoProvider: saveMemo 호출 후 1초 이내 파일 기록 완료
- 저장 실패 시 오류 상태 반환

**우선순위:** P0

---

#### MEMO-003: 메인 화면 구현 (SCR-02)

**설명:** 오늘 날짜 메모 목록과 하단 액션 버튼(음성·사진·위치)을 표시하는 메인 화면을 구현한다.

**인수 조건:**
- 앱바: 목록 아이콘(SCR-04 이동) + 설정 아이콘(SCR-06 이동)
- 날짜 헤더(18sp) + 오늘 .md 파일 파싱 결과를 순서대로 렌더링
- 현황 블록과 메모 엔트리 카드 표시 (파일 순서 유지)
- 빈 상태 시 EmptyStateView 표시
- 하단 액션 바: 음성(SCR-03), 사진(OS 인텐트), 위치(ConfirmDialog) 버튼
- showLocationButton=false 시 위치 버튼 숨김, 음성·사진 버튼 재배치

**우선순위:** P0

---

#### MEMO-004: 텍스트 메모 입력 시트 구현 (SCR-03, 텍스트 모드)

**설명:** 바텀시트 형태의 메모 입력 UI에서 텍스트를 직접 입력하고 저장하는 기능을 구현한다.

**인수 조건:**
- Modal Bottom Sheet, 화면의 60% 높이 (키보드 자동 조정)
- 텍스트 필드(최소 높이 120dp, 멀티라인, 자동 포커스)
- 저장 버튼 탭 시 GPS 좌표 조회 → .md append → 시트 닫힘 → 메인 목록 갱신
- 취소 또는 드래그 다운 시 저장 없이 닫힘

**우선순위:** P0

---

#### MEMO-005: 음성 메모 구현 (SCR-03, 음성 모드)

**설명:** 메모 입력 시트에서 🎤 버튼을 누르는 동안 음성을 인식하고 텍스트 필드에 결과를 삽입하는 기능을 구현한다.

**인수 조건:**
- speech_to_text 패키지의 디바이스 내장 엔진 사용 (오프라인 동작)
- GestureDetector onLongPressStart/End로 녹음 시작/종료
- 인식 중 버튼 배경색 변경으로 상태 표시
- 인식 완료: 기존 텍스트 뒤에 결과 이어 붙임
- 발화 종료 후 2초 이내 텍스트 표시
- 마이크 권한 없음 시 🎤 버튼 비활성화 + 안내 메시지
- 인식 실패 시 오류 메시지 표시 ("음성을 인식하지 못했습니다"), 재시도 가능

**우선순위:** P0

---

### LOCATION — 현황 블록

#### LOCATION-001: GPS 서비스 구현

**설명:** LocationService 인터페이스와 geolocator 구현체, locationProvider를 작성한다.

**인수 조건:**
- LocationService: getCurrentLocation() → LocationStatus(lat/lng) 반환
- LocationServiceImpl: geolocator로 정밀 GPS 조회, 타임아웃 5초
- 타임아웃 시 마지막 캐시 좌표 반환 (캐시도 없으면 null)
- locationProvider: 캐시 좌표 보관, GPS 비활성화 시 null 반환

**우선순위:** P0

---

#### LOCATION-002: 현황 블록 추가 기능 구현

**설명:** 위치 추가 버튼 탭 시 확인 팝업을 표시하고, 확인 시 현황 블록을 .md 파일에 추가하는 기능을 구현한다.

**인수 조건:**
- ConfirmDialog("위치 추가", "현재 위치로 현황 블록을 추가하시겠습니까?") 표시
- 확인 시 아래 형식의 현황 블록 .md에 append:
  ```
  ## 현황 (HH:mm 장소)
  - 📍 시/군/면 주소
  - 🌡 기온: -°C | 🌊 -물 (- --:--) | 💧 수온 -°C
  - 관측소: - (-.--km)
  ```
- Phase 1: 주소는 좌표 그대로 표시(역지오코딩 미구현), 기상·물때·수온은 `-` 플레이스홀더
- GPS 권한 없으면 주소 없이 시각만 포함한 현황 블록 추가
- showLocationButton 설정에 따라 버튼 표시/숨김 연동

**우선순위:** P0

---

### PHOTO — 사진 첨부

#### PHOTO-001: 사진 서비스 구현

**설명:** PhotoService 인터페이스와 image_picker + 파일 복사 구현체를 작성한다.

**인수 조건:**
- PhotoService: pickAndSave(date, time) → 저장된 상대 경로 반환
- PhotoServiceImpl: image_picker로 카메라 촬영 또는 갤러리 선택
- 사진 저장 경로: `[savePath]/photos/YYYY-MM-DD_HH-mm-ss.jpg`
- photos/ 디렉토리 없으면 자동 생성
- 파일 복사 성공 후 .md에 이미지 링크 append (원자성 보장)
- 복사 실패 시 복사된 파일 삭제 후 오류 반환

**우선순위:** P0

---

#### PHOTO-002: 사진 첨부 UI 연동 (SCR-02)

**설명:** 메인 화면 사진 버튼 탭 시 카메라/갤러리 선택 → 저장 → 메인 목록 갱신 흐름을 구현한다.

**인수 조건:**
- 사진 버튼 탭 시 OS 카메라/갤러리 선택 팝업 표시
- 사진 선택/촬영 후 photoProvider를 통해 저장
- 저장 완료 후 메인 화면 메모 목록 갱신
- 이미지 링크만 있는 메모도 타임스탬프 + 좌표 헤더 포함
- 메인 화면에서 사진 썸네일(높이 120dp) 표시, 탭 시 OS 이미지 뷰어 열기

**우선순위:** P0

---

### FILE — 파일 목록 및 관리

#### FILE-001: 파일 목록 Repository 및 Provider 구현

**설명:** FileListRepository 인터페이스와 디렉토리 스캔 구현체, fileListProvider를 작성한다.

**인수 조건:**
- FileListRepository: listFiles(savePath) → FileSummary 목록 반환
- 파일명 YYYY-MM-DD.md 패턴 파싱, 날짜 내림차순 정렬
- entryCount: 파일 전체 파싱 없이 줄 단위 스캔(`### HH:mm` 헤더 수 카운트)
- 100개 파일 기준 1초 이내 로딩
- fileListProvider: settingsProvider의 savePath를 참조

**우선순위:** P0

---

#### FILE-002: 파일 목록 화면 구현 (SCR-04)

**설명:** 날짜 내림차순 파일 목록과 길게 누르기 컨텍스트 메뉴(이름 변경·삭제)를 구현한다.

**인수 조건:**
- 각 항목: 날짜(16sp) + 상대 날짜("오늘"/"어제"/"N일 전"/YYYY-MM-DD) + 메모 개수, 최소 높이 64dp
- 사용자 변경 파일명도 displayName으로 표시
- 빈 상태 시 EmptyStateView 표시
- 길게 누르기: 이름 변경 / 삭제 컨텍스트 메뉴
- 이름 변경 팝업: 현재 이름 초기값, 날짜 외 문자열 허용, 저장 시 파일명 변경 후 목록 갱신
- 삭제 확인 팝업: "연결된 사진도 함께 삭제" 체크박스 포함, 확인 시 파일 삭제 후 목록 갱신

**우선순위:** P0

---

#### FILE-003: 파일 뷰어 화면 구현 (SCR-05)

**설명:** 선택한 .md 파일의 내용을 커스텀 파싱으로 렌더링하는 뷰어 화면을 구현한다.

**인수 조건:**
- 마크다운 라이브러리 미사용, 원문 기반 커스텀 파싱
- `## 현황` → LocationStatusCard 위젯
- `### HH:mm | 🛰 ...` → 타임스탬프 헤더(13sp Bold) + 본문(15sp, 줄간격 1.4)
- `![](photos/...)` → 인라인 이미지(최대 높이 240dp), 파일 존재 확인 후 표시, 탭 시 OS 이미지 뷰어
- `---` → Divider
- SCR-04 및 SCR-02(오늘 날짜 카드 탭) 양쪽에서 진입 가능

**우선순위:** P0

---

#### FILE-004: 파일 삭제 시 연결 사진 처리

**설명:** 파일 삭제 시 "연결된 사진도 삭제" 체크박스를 선택한 경우, .md 파일 내 photos/ 링크를 파싱하여 해당 이미지 파일만 삭제한다.

**인수 조건:**
- .md 파일 내 `![](photos/YYYY-MM-DD_...)` 패턴을 파싱하여 파일 목록 추출
- 해당 파일만 개별 삭제 (photos/ 폴더 전체 삭제 금지)
- 파일이 이미 없는 경우 무시하고 진행

**우선순위:** P1

---

## 3. Story별 Task 분해

---

### CORE Epic Tasks

#### CORE-001: Flutter 프로젝트 초기화 및 패키지 설정

| Task ID | 작업 내용 | 복잡도 | 의존 Task |
|---------|----------|--------|----------|
| CORE-001-T1 | `flutter create vo_rec` 실행, android minSdkVersion=26 설정 | S | — | ✓tested |
| CORE-001-T2 | pubspec.yaml에 8개 패키지 추가, `flutter pub get` 실행 | S | CORE-001-T1 | ✓tested |
| CORE-001-T3 | lib/ 하위 core/, features/(permission/memo/location/photo/file_list/settings), home/ 폴더 구조 생성 | S | CORE-001-T1 | ✓tested |
| CORE-001-T4 | AndroidManifest.xml에 마이크·위치·카메라·저장소 권한 선언 | S | CORE-001-T1 | ✓tested |

#### CORE-002: 앱 진입점, 라우팅 및 다크 테마 설정

| Task ID | 작업 내용 | 복잡도 | 의존 Task |
|---------|----------|--------|----------|
| CORE-002-T1 | main.dart: ProviderScope 래핑, runApp(App()) | S | CORE-001-T2 | ✓tested |
| CORE-002-T2 | app_theme.dart: 다크 테마 ColorScheme, 폰트 정의 | S | CORE-001-T3 | ✓tested |
| CORE-002-T3 | app_router.dart: GoRouter로 SCR-01~06 라우트 정의 (플레이스홀더 위젯으로 초기 등록) | M | CORE-001-T2, CORE-001-T3 | ✓tested |
| CORE-002-T4 | app.dart: MaterialApp.router 설정, 테마·라우터 연결 | S | CORE-002-T1, CORE-002-T2, CORE-002-T3 | ✓tested |
| CORE-002-T5 | app_constants.dart: 날짜 포맷, 파일 경로 패턴, GPS 타임아웃(5초) 상수 정의 | S | CORE-001-T3 | ✓tested |

#### CORE-003: 공통 유틸 및 공통 컴포넌트 구현

| Task ID | 작업 내용 | 복잡도 | 의존 Task |
|---------|----------|--------|----------|
| CORE-003-T1 | date_formatter.dart: YYYY-MM-DD, HH:mm, 상대 날짜 포맷 유틸 | S | CORE-001-T3 | ✓tested |
| CORE-003-T2 | file_name_parser.dart: YYYY-MM-DD.md 패턴 파싱 유틸 | S | CORE-001-T3 | ✓tested |
| CORE-003-T3 | ActionButton 위젯: 탭 영역 72×72dp, 아이콘 32dp, 레이블 12sp, 원형, enabled 상태 지원 | S | CORE-002-T2 | ✓tested |
| CORE-003-T4 | ConfirmDialog 위젯: title/content/confirmLabel/cancelLabel/isDestructive/extra 파라미터 | S | CORE-002-T2 | ✓tested |
| CORE-003-T5 | EmptyStateView 위젯: message/subMessage 중앙 정렬 | S | CORE-002-T2 | ✓tested |
| CORE-003-T6 | MemoEntryCard 위젯: photoPath/text 분기, 좌표 표시, maxLines 지원 | M | CORE-002-T2 | ✓tested |
| CORE-003-T7 | LocationStatusCard 위젯: null 필드 `-` 플레이스홀더, showMoveTime 지원 | S | CORE-002-T2 | ✓tested |
| CORE-003-T8 | PermissionStatusChip 위젯: 허용(초록)/거부(빨강) 상태 칩 | S | CORE-002-T2 | ✓tested |

---

### PERM Epic Tasks

#### PERM-001: 권한 요청 화면 구현 (SCR-01)

| Task ID | 작업 내용 | 복잡도 | 의존 Task |
|---------|----------|--------|----------|
| PERM-001-T1 | permission_service.dart: 인터페이스 정의 (checkStatus, requestAll) | S | CORE-001-T3 | ✓tested |
| PERM-001-T2 | permission_service_impl.dart: permission_handler로 구현 | S | PERM-001-T1 | ✓tested |
| PERM-001-T3 | permission_provider.dart: 권한별 PermissionStatus Riverpod 상태 | S | PERM-001-T2 | ✓tested |
| PERM-001-T4 | permission_gate.dart: 미허용 권한 체크 후 SCR-01/SCR-02 분기 위젯 | S | PERM-001-T3 | ✓tested |
| PERM-001-T5 | SCR-01 권한 요청 화면 UI: 4개 권한 카드, 권한 허용하기 버튼(56dp), 나중에 하기 버튼(48dp) | M | PERM-001-T3, CORE-002-T3 | ✓tested |
| PERM-001-T6 | 권한 허용하기 버튼 탭 시 순차 요청 로직, 완료 후 SCR-02 이동 | S | PERM-001-T5 | ✓tested |

---

### SETTINGS Epic Tasks

#### SETTINGS-001: 설정 도메인 및 데이터 레이어 구현

| Task ID | 작업 내용 | 복잡도 | 의존 Task |
|---------|----------|--------|----------|
| SETTINGS-001-T1 | app_settings.dart: AppSettings 모델 (savePath, showLocationButton) | S | CORE-001-T3 | ✓tested |
| SETTINGS-001-T2 | settings_repository.dart: 인터페이스 정의 (load, save) | S | SETTINGS-001-T1 | ✓tested |
| SETTINGS-001-T3 | settings_repository_impl.dart: shared_preferences 구현, 기본값 path_provider 연동 | M | SETTINGS-001-T2 | ✓tested |
| SETTINGS-001-T4 | settings_provider.dart: settingsProvider Riverpod 정의 | S | SETTINGS-001-T3 | ✓tested |

#### SETTINGS-002: 설정 화면 구현 (SCR-06)

| Task ID | 작업 내용 | 복잡도 | 의존 Task |
|---------|----------|--------|----------|
| SETTINGS-002-T1 | SCR-06 UI 레이아웃: 섹션(저장/표시/권한) + 각 항목 배치 | M | SETTINGS-001-T4, CORE-003-T8, CORE-002-T3 | ✓tested |
| SETTINGS-002-T2 | 저장 경로 변경 다이얼로그: TextField + 안내 텍스트(파일 이동 없음) + 저장 로직 | S | SETTINGS-002-T1 | ✓tested |
| SETTINGS-002-T3 | 위치 버튼 SwitchListTile: showLocationButton 토글 즉시 저장 | S | SETTINGS-002-T1 | ✓tested |
| SETTINGS-002-T4 | 권한 상태 표시 + 거부된 권한 탭 시 openAppSettings() 호출 | S | SETTINGS-002-T1, PERM-001-T3 | ✓tested |

---

### MEMO Epic Tasks

#### MEMO-001: .md 파일 직렬화/파싱 구현

| Task ID | 작업 내용 | 복잡도 | 의존 Task |
|---------|----------|--------|----------|
| MEMO-001-T1 | MemoEntry 모델: timestamp, latitude, longitude, text, photoPath | S | CORE-001-T3 | ✓tested |
| MEMO-001-T2 | DayFile 모델: date, filePath, entries, locationBlocks | S | MEMO-001-T1 | ✓tested |
| MEMO-001-T3 | md_serializer.dart 쓰기: MemoEntry → .md 블록 문자열 직렬화 (GPS 유무 분기) | M | MEMO-001-T1, CORE-003-T1 | ✓tested |
| MEMO-001-T4 | md_serializer.dart 읽기: `---` 블록 분리 → MemoEntry/LocationStatus 파싱 (정규식 기반) | M | MEMO-001-T2 | ✓tested |

#### MEMO-002: 메모 Repository 및 Provider 구현

| Task ID | 작업 내용 | 복잡도 | 의존 Task |
|---------|----------|--------|----------|
| MEMO-002-T1 | memo_repository.dart: 인터페이스 정의 (appendEntry, loadDayFile) | S | MEMO-001-T1 | ✓tested |
| MEMO-002-T2 | memo_repository_impl.dart: 파일 없으면 헤더 생성 후 append, 파일 I/O | M | MEMO-002-T1, MEMO-001-T3 | ✓tested |
| MEMO-002-T3 | memo_provider.dart: saveMemo 액션, 저장 성공/실패 상태 | S | MEMO-002-T2 | ✓tested |

#### MEMO-003: 메인 화면 구현 (SCR-02)

| Task ID | 작업 내용 | 복잡도 | 의존 Task |
|---------|----------|--------|----------|
| MEMO-003-T1 | home_screen.dart 기본 레이아웃: 앱바 + ListView + 하단 액션 바 | M | CORE-002-T3, CORE-003-T3, CORE-003-T5 | ✓tested |
| MEMO-003-T2 | 오늘 .md 파일 파싱 후 MemoEntryCard + LocationStatusCard 혼합 렌더링 | M | MEMO-001-T4, CORE-003-T6, CORE-003-T7, MEMO-003-T1 | ✓tested |
| MEMO-003-T3 | 하단 액션 바 버튼 연동: 음성(SCR-03), 사진(OS 인텐트), 위치(ConfirmDialog) | M | MEMO-003-T1, CORE-003-T4, SETTINGS-001-T4 | ✓tested |
| MEMO-003-T4 | showLocationButton 설정 연동: 위치 버튼 표시/숨김, 버튼 재배치 | S | MEMO-003-T3, SETTINGS-001-T4 | ✓tested |
| MEMO-003-T5 | 앱바 네비게이션: 목록 아이콘 → SCR-04, 설정 아이콘 → SCR-06 | S | MEMO-003-T1, CORE-002-T3 | ✓tested |

#### MEMO-004: 텍스트 메모 입력 시트 구현 (SCR-03, 텍스트 모드)

| Task ID | 작업 내용 | 복잡도 | 의존 Task |
|---------|----------|--------|----------|
| MEMO-004-T1 | memo_input_sheet.dart Modal Bottom Sheet UI: 드래그 핸들, 텍스트 필드(120dp), 저장/취소 버튼 | M | CORE-002-T2, CORE-002-T3 | ✓tested |
| MEMO-004-T2 | 저장 버튼 로직: GPS 조회 → appendEntry → 시트 닫힘 → 메인 목록 갱신 | M | MEMO-004-T1, MEMO-002-T3, LOCATION-001-T3 | ✓tested |

#### MEMO-005: 음성 메모 구현 (SCR-03, 음성 모드)

| Task ID | 작업 내용 | 복잡도 | 의존 Task |
|---------|----------|--------|----------|
| MEMO-005-T1 | voice_input_provider.dart: speech_to_text 패키지 연동, 인식 상태 관리 | M | CORE-001-T2 | ✓tested |
| MEMO-005-T2 | 🎤 버튼 GestureDetector: onLongPressStart 녹음 시작, onLongPressEnd 종료 | S | MEMO-005-T1, MEMO-004-T1 | ✓tested |
| MEMO-005-T3 | 음성 인식 결과 텍스트 필드 삽입 (기존 텍스트 뒤에 이어 붙임), 버튼 상태 시각화 | S | MEMO-005-T2 | ✓tested |
| MEMO-005-T4 | 마이크 권한 없음 처리: 버튼 비활성화, 안내 메시지 표시 | S | MEMO-005-T2, PERM-001-T3 | ✓tested |
| MEMO-005-T5 | 음성 인식 실패 오류 메시지 표시 및 재시도 허용 | S | MEMO-005-T3 | ✓tested |

---

### LOCATION Epic Tasks

#### LOCATION-001: GPS 서비스 구현

| Task ID | 작업 내용 | 복잡도 | 의존 Task |
|---------|----------|--------|----------|
| LOCATION-001-T1 | location_status.dart: LocationStatus 모델 (timestamp, latitude, longitude, + Phase2 null 필드) | S | CORE-001-T3 |
| LOCATION-001-T2 | location_service.dart: 인터페이스 정의 (getCurrentLocation) | S | LOCATION-001-T1 | ✓tested |
| LOCATION-001-T3 | location_service_impl.dart: geolocator 구현, 타임아웃 5초, 캐시 좌표 반환 | M | LOCATION-001-T2 | ✓tested |
| LOCATION-001-T4 | location_provider.dart: locationProvider Riverpod 정의, 캐시 상태 관리 | S | LOCATION-001-T3 | ✓tested |

#### LOCATION-002: 현황 블록 추가 기능 구현

| Task ID | 작업 내용 | 복잡도 | 의존 Task |
|---------|----------|--------|----------|
| LOCATION-002-T1 | md_serializer.dart에 LocationStatus → 현황 블록 직렬화 추가 | S | MEMO-001-T3, LOCATION-001-T1 | ✓tested |
| LOCATION-002-T2 | memo_repository_impl.dart에 appendLocationBlock 메서드 추가 | S | MEMO-002-T2, LOCATION-002-T1 | ✓tested |
| LOCATION-002-T3 | 위치 추가 버튼 ConfirmDialog 표시 및 확인 시 appendLocationBlock 호출 연동 (SCR-02) | S | LOCATION-002-T2, MEMO-003-T3, CORE-003-T4 | ✓tested |

---

### PHOTO Epic Tasks

#### PHOTO-001: 사진 서비스 구현

| Task ID | 작업 내용 | 복잡도 | 의존 Task |
|---------|----------|--------|----------|
| PHOTO-001-T1 | photo_service.dart: 인터페이스 정의 (pickAndSave) | S | CORE-001-T3 | ✓tested |
| PHOTO-001-T2 | photo_service_impl.dart: image_picker 촬영/갤러리, photos/ 복사, 원자성 보장 | M | PHOTO-001-T1, SETTINGS-001-T4 | ✓tested |
| PHOTO-001-T3 | photo_provider.dart: photoProvider, memoProvider 연동으로 이미지 링크 append | S | PHOTO-001-T2, MEMO-002-T3 | ✓tested |

#### PHOTO-002: 사진 첨부 UI 연동 (SCR-02)

| Task ID | 작업 내용 | 복잡도 | 의존 Task |
|---------|----------|--------|----------|
| PHOTO-002-T1 | 사진 버튼 탭 → photoProvider.pickAndSave → 메인 목록 갱신 연동 | S | PHOTO-001-T3, MEMO-003-T3 | ✓tested |
| PHOTO-002-T2 | 메인 화면 MemoEntryCard에서 사진 썸네일(120dp) 표시, 탭 시 OS 이미지 뷰어 실행 | S | PHOTO-002-T1, CORE-003-T6 | ✓tested |

---

### FILE Epic Tasks

#### FILE-001: 파일 목록 Repository 및 Provider 구현

| Task ID | 작업 내용 | 복잡도 | 의존 Task |
|---------|----------|--------|----------|
| FILE-001-T1 | file_summary.dart: FileSummary 모델 (date, filePath, displayName, entryCount) | S | CORE-001-T3 | ✓tested |
| FILE-001-T2 | file_list_repository.dart: 인터페이스 정의 (listFiles) | S | FILE-001-T1 | ✓tested |
| FILE-001-T3 | file_list_repository_impl.dart: 디렉토리 스캔, 날짜 내림차순 정렬, entryCount 줄 스캔 최적화 | M | FILE-001-T2, CORE-003-T2 | ✓tested |
| FILE-001-T4 | file_list_provider.dart: fileListProvider, settingsProvider.savePath 참조 | S | FILE-001-T3, SETTINGS-001-T4 | ✓tested |

#### FILE-002: 파일 목록 화면 구현 (SCR-04)

| Task ID | 작업 내용 | 복잡도 | 의존 Task |
|---------|----------|--------|----------|
| FILE-002-T1 | SCR-04 기본 UI: ListView 항목(날짜 16sp + 상대 날짜 + 메모 개수, 최소 64dp), EmptyStateView | M | FILE-001-T4, CORE-003-T1, CORE-003-T5, CORE-002-T3 | ✓tested |
| FILE-002-T2 | 항목 탭 시 SCR-05 이동 | S | FILE-002-T1 | ✓tested |
| FILE-002-T3 | 길게 누르기 컨텍스트 메뉴: 이름 변경 팝업 (TextField 초기값, 저장 시 파일명 변경) | M | FILE-002-T1, CORE-003-T4 | ✓tested |
| FILE-002-T4 | 삭제 확인 팝업: "연결된 사진도 삭제" 체크박스, 확인 시 파일 삭제 후 목록 갱신 | M | FILE-002-T1, CORE-003-T4 | ✓tested |

#### FILE-003: 파일 뷰어 화면 구현 (SCR-05)

| Task ID | 작업 내용 | 복잡도 | 의존 Task |
|---------|----------|--------|----------|
| FILE-003-T1 | SCR-05 기본 레이아웃: 앱바(날짜/파일명) + 스크롤 뷰 | S | CORE-002-T3 | ✓tested |
| FILE-003-T2 | 커스텀 파싱 렌더러: `## 현황` → LocationStatusCard, `### HH:mm` → 타임스탬프+본문, `---` → Divider | M | FILE-003-T1, MEMO-001-T4, CORE-003-T6, CORE-003-T7 | ✓tested |
| FILE-003-T3 | 인라인 이미지 렌더링: `![](photos/...)` → 이미지 위젯(최대 240dp), 파일 존재 확인, 탭 시 OS 뷰어 | M | FILE-003-T2 | ✓tested |

#### FILE-004: 파일 삭제 시 연결 사진 처리

| Task ID | 작업 내용 | 복잡도 | 의존 Task |
|---------|----------|--------|----------|
| FILE-004-T1 | file_list_repository_impl.dart에 deleteFile(path, deletePhotos) 메서드 추가: .md 내 photos/ 링크 파싱 후 개별 삭제 | M | FILE-001-T3, MEMO-001-T4 | ✓tested |
| FILE-004-T2 | SCR-04 삭제 팝업에서 체크박스 값을 deleteFile에 전달하는 연동 | S | FILE-004-T1, FILE-002-T4 | ✓tested |

---

## 4. 개발 순서 추천 (Sprint 단위)

의존 관계를 고려한 순서입니다. 각 Sprint는 1주(5일) 기준입니다.

---

### Sprint 1 — 기반 구조 및 설정 (5일)

**목표:** 앱이 실행되고 설정이 저장되는 최소 골격 완성

| Task ID | 설명 | 복잡도 |
|---------|------|--------|
| CORE-001-T1 | 프로젝트 생성, minSdkVersion=26 | S |
| CORE-001-T2 | pubspec.yaml 패키지 추가 | S |
| CORE-001-T3 | 폴더 구조 생성 | S |
| CORE-001-T4 | AndroidManifest 권한 선언 | S |
| CORE-002-T5 | app_constants.dart | S |
| CORE-002-T1 | main.dart ProviderScope | S |
| CORE-002-T2 | app_theme.dart 다크 테마 | S |
| CORE-002-T3 | app_router.dart 라우트 정의 | M |
| CORE-002-T4 | app.dart 통합 | S |
| SETTINGS-001-T1 | AppSettings 모델 | S |
| SETTINGS-001-T2 | SettingsRepository 인터페이스 | S |
| SETTINGS-001-T3 | SettingsRepositoryImpl | M |
| SETTINGS-001-T4 | settingsProvider | S |

**검증:** 앱 실행 → 다크 테마 표시 → 설정 저장·로드 동작 확인

---

### Sprint 2 — 권한 관리 및 공통 컴포넌트 (5일)

**목표:** 권한 요청 흐름 완성 + 공통 UI 컴포넌트 준비

| Task ID | 설명 | 복잡도 |
|---------|------|--------|
| PERM-001-T1 | PermissionService 인터페이스 | S |
| PERM-001-T2 | PermissionServiceImpl | S |
| PERM-001-T3 | permissionProvider | S |
| PERM-001-T4 | PermissionGate 위젯 | S |
| PERM-001-T5 | SCR-01 권한 요청 화면 UI | M |
| PERM-001-T6 | 순차 권한 요청 로직 + SCR-02 이동 | S |
| CORE-003-T1 | date_formatter.dart | S |
| CORE-003-T2 | file_name_parser.dart | S |
| CORE-003-T3 | ActionButton 위젯 | S |
| CORE-003-T4 | ConfirmDialog 위젯 | S |
| CORE-003-T5 | EmptyStateView 위젯 | S |
| CORE-003-T8 | PermissionStatusChip 위젯 | S |

**검증:** 앱 최초 실행 → SCR-01 표시 → 권한 처리 → SCR-02 이동 확인

---

### Sprint 3 — 메모 핵심 로직 및 메인 화면 골격 (5일)

**목표:** .md 파일 읽기/쓰기 완성 + 메인 화면 골격 표시

| Task ID | 설명 | 복잡도 |
|---------|------|--------|
| MEMO-001-T1 | MemoEntry 모델 | S |
| MEMO-001-T2 | DayFile 모델 | S |
| MEMO-001-T3 | md_serializer 쓰기 | M |
| MEMO-001-T4 | md_serializer 읽기 | M |
| MEMO-002-T1 | MemoRepository 인터페이스 | S |
| MEMO-002-T2 | MemoRepositoryImpl | M |
| MEMO-002-T3 | memoProvider | S |
| CORE-003-T6 | MemoEntryCard 위젯 | M |
| CORE-003-T7 | LocationStatusCard 위젯 | S |
| MEMO-003-T1 | home_screen.dart 기본 레이아웃 | M |
| MEMO-003-T5 | 앱바 네비게이션 연동 | S |

**검증:** .md 직렬화/파싱 단위 테스트 통과, 메인 화면 렌더링 확인

---

### Sprint 4 — 텍스트·음성 메모 입력 (5일)

**목표:** 텍스트 메모와 음성 메모 저장 완성

| Task ID | 설명 | 복잡도 |
|---------|------|--------|
| LOCATION-001-T1 | LocationStatus 모델 | S |
| LOCATION-001-T2 | LocationService 인터페이스 | S |
| LOCATION-001-T3 | LocationServiceImpl (geolocator, 타임아웃·캐시) | M |
| LOCATION-001-T4 | locationProvider | S |
| MEMO-004-T1 | memo_input_sheet.dart UI | M |
| MEMO-004-T2 | 저장 로직 연동 | M |
| MEMO-003-T2 | 메인 화면 메모 목록 렌더링 | M |
| MEMO-003-T3 | 하단 액션 바 버튼 연동 | M |
| MEMO-003-T4 | showLocationButton 설정 연동 | S |
| MEMO-005-T1 | voice_input_provider.dart | M |
| MEMO-005-T2 | 🎤 버튼 GestureDetector | S |
| MEMO-005-T3 | 음성 결과 텍스트 삽입 + 상태 시각화 | S |
| MEMO-005-T4 | 마이크 권한 없음 처리 | S |
| MEMO-005-T5 | 음성 실패 오류 메시지 | S |

**검증:** 텍스트 메모 저장 → .md 파일 내용 확인, 음성 인식 후 저장 확인

---

### Sprint 5 — 사진 첨부 및 현황 블록 (4일)

**목표:** 사진 첨부와 위치 현황 블록 추가 완성

| Task ID | 설명 | 복잡도 |
|---------|------|--------|
| PHOTO-001-T1 | PhotoService 인터페이스 | S |
| PHOTO-001-T2 | PhotoServiceImpl (image_picker + 파일 복사 원자성) | M |
| PHOTO-001-T3 | photoProvider, memoProvider 연동 | S |
| PHOTO-002-T1 | 사진 버튼 탭 → 저장 → 목록 갱신 | S |
| PHOTO-002-T2 | 썸네일 표시 + OS 이미지 뷰어 탭 | S |
| LOCATION-002-T1 | LocationStatus 현황 블록 직렬화 | S |
| LOCATION-002-T2 | appendLocationBlock 메서드 추가 | S |
| LOCATION-002-T3 | 위치 추가 버튼 ConfirmDialog 연동 | S |

**검증:** 사진 촬영 → photos/ 저장 → .md 링크 확인, 현황 블록 추가 확인

---

### Sprint 6 — 파일 목록·뷰어·설정 화면 (5일)

**목표:** 파일 관리 기능과 설정 화면 완성 → Phase 1 MVP 완료

| Task ID | 설명 | 복잡도 |
|---------|------|--------|
| FILE-001-T1 | FileSummary 모델 | S |
| FILE-001-T2 | FileListRepository 인터페이스 | S |
| FILE-001-T3 | FileListRepositoryImpl (디렉토리 스캔·최적화) | M |
| FILE-001-T4 | fileListProvider | S |
| FILE-002-T1 | SCR-04 목록 UI | M |
| FILE-002-T2 | SCR-04 → SCR-05 이동 | S |
| FILE-002-T3 | 이름 변경 팝업 | M |
| FILE-002-T4 | 삭제 확인 팝업 | M |
| FILE-004-T1 | deleteFile + 연결 사진 처리 | M |
| FILE-004-T2 | 삭제 팝업 체크박스 연동 | S |
| FILE-003-T1 | SCR-05 기본 레이아웃 | S |
| FILE-003-T2 | 커스텀 파싱 렌더러 | M |
| FILE-003-T3 | 인라인 이미지 렌더링 | M |
| SETTINGS-002-T1 | SCR-06 UI 레이아웃 | M |
| SETTINGS-002-T2 | 저장 경로 변경 다이얼로그 | S |
| SETTINGS-002-T3 | 위치 버튼 스위치 | S |
| SETTINGS-002-T4 | 권한 상태 표시 + OS 설정 이동 | S |

**검증:**
- SCR-04: 파일 목록 날짜 내림차순 표시, 이름 변경·삭제 동작
- SCR-05: 현황 블록·메모·이미지 렌더링, OS 이미지 뷰어 탭
- SCR-06: 저장 경로 변경 영속, 위치 버튼 토글 반영
- Phase 1 전체 인수 조건 점검

---

## 요약 통계

| 구분 | 수량 |
|------|------|
| Epic (Phase 1) | 6개 |
| Story | 15개 |
| Task (전체) | 74개 |
| Task — S (0.5일 이하) | 46개 |
| Task — M (1~2일) | 28개 |
| Task — L (3일 이상) | 0개 |
| 예상 Sprint 수 | 6 Sprint (약 6주) |
