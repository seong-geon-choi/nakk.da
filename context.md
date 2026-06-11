# context.md — vo-rec 개발 이력

**최종 업데이트:** 2026-06-11 (세션 D)

---

## 세션 이력 요약

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
