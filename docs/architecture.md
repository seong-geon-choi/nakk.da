# 아키텍처 설계서: vo-rec

**버전:** 2.2  
**최초 작성:** 2026-06-02  
**최종 수정:** 2026-06-11  
**플랫폼:** Android (Flutter)

---

## 1. 기술 스택

### Flutter / Dart 버전

| 항목 | 버전 |
|------|------|
| Flutter | 3.x (stable 최신) |
| Dart | 3.x |
| Android 최소 SDK | 26 (Android 8.0) |
| Android 타겟 SDK | 36 |

### 패키지 목록

| 패키지 | 버전 | 선택 이유 |
|--------|------|-----------|
| `flutter_riverpod` | ^2.x | 단순하고 명확한 상태관리. 타입 안전, 의존성 낮음 |
| `go_router` | ^14.x | Flutter 공식 권장 라우터. 선언적 라우팅 |
| `speech_to_text` | ^7.x | 디바이스 내장 엔진. 오프라인 동작, 실시간 interim 결과 지원 |
| `image_picker` | ^1.x | 카메라/갤러리 접근 표준 패키지 |
| `geolocator` | ^13.x | Android GPS 접근 표준. 정밀 위치 + 타임아웃 설정 |
| `permission_handler` | ^11.x | 마이크·위치·카메라·저장소 권한 통합 처리 |
| `path_provider` | ^2.x | 앱 외부 저장소 경로 획득 |
| `shared_preferences` | ^2.x | 설정값 영속 저장 |
| `http` | ^1.x | 기상청·해양조사원 공공 API 호출 |
| `geocoding` | ^3.x | GPS 좌표 → 주소 역지오코딩 |
| `camera` | ^0.11.x | 카메라 화면 (사진 촬영 + 동영상 녹화) |
| `flutter_map` | ^7.x | OpenStreetMap 기반 지도 표시 |
| `latlong2` | ^0.9.x | LatLng 좌표 타입 (flutter_map 의존) |
| `video_player` | ^2.9.x | 동영상 전체화면 재생 |
| `video_thumbnail` | ^0.5.x | 동영상 썸네일 첫 프레임 추출 |
| `photo_manager` | ^3.4.x | 커스텀 갤러리 피커 (사진·동영상 통합 조회) |
| `google_sign_in` | ^6.x | Google OAuth 로그인 (Drive 백업용) |
| `googleapis` | ^13.x | Google Drive REST API v3 |
| `connectivity_plus` | ^6.x | 네트워크 연결 상태 확인 (백업 전 체크) |
| `flutter_launcher_icons` | ^0.14.x | 앱 아이콘 생성 (dev) |

---

## 2. 폴더 구조

feature-first 방식. 각 기능은 독립적인 폴더 아래 presentation / domain / data 레이어를 갖습니다.

```
lib/
├── main.dart
├── app.dart
│
├── core/
│   ├── constants/
│   │   ├── app_constants.dart
│   │   └── api_keys.dart              # 공공 API 기본 키
│   ├── theme/
│   │   └── app_theme.dart
│   ├── router/
│   │   └── app_router.dart
│   ├── screens/
│   │   └── gallery_picker_screen.dart # 커스텀 갤러리 (photo_manager, 탭 필터)
│   └── utils/
│       ├── date_formatter.dart
│       ├── file_name_parser.dart
│       └── media_scanner.dart         # MediaStore 저장·갤러리 피커 (Kotlin 채널 호출)
│
├── features/
│   ├── permission/
│   ├── memo/
│   │   ├── domain/models/
│   │   │   ├── memo_entry.dart
│   │   │   └── day_file.dart
│   │   ├── data/
│   │   │   ├── memo_repository_impl.dart
│   │   │   └── md_serializer.dart
│   │   └── presentation/
│   │       ├── memo_input_sheet.dart
│   │       ├── memo_provider.dart
│   │       ├── voice_input_provider.dart
│   │       └── location_edit_sheet.dart
│   │
│   ├── location/
│   │   ├── domain/models/location_status.dart
│   │   ├── data/
│   │   │   ├── location_service_impl.dart
│   │   │   └── reverse_geocoder.dart  # geocoding 패키지 래퍼
│   │   └── presentation/location_provider.dart
│   │
│   ├── photo/
│   │   ├── domain/photo_service.dart  # pickImage / pickVideoFromGallery 인터페이스
│   │   ├── data/photo_service_impl.dart
│   │   └── presentation/
│   │       ├── photo_provider.dart    # MediaStore 저장 + GPS 기록
│   │       └── camera_ruler_screen.dart  # 사진·동영상 모드 전환, 해상도 선택
│   │
│   ├── weather/
│   │   └── data/weather_service.dart  # 기상청 API
│   │
│   ├── tide/
│   │   ├── domain/models/tide_station.dart
│   │   ├── data/
│   │   │   ├── tide_service.dart      # 해양조사원 API
│   │   │   └── tide_station_data.dart # 관측소 목록 내장 데이터
│   │
│   ├── map/
│   │   └── presentation/map_screen.dart  # flutter_map + 클러스터링
│   │
│   ├── file_list/
│   └── settings/
│       ├── domain/models/app_settings.dart  # savePath + photoSavePath
│       ├── data/settings_repository_impl.dart
│       └── presentation/
│           ├── settings_screen.dart
│           └── settings_provider.dart
│
└── home/
    └── presentation/home_screen.dart
```

```
android/app/src/main/kotlin/com/vorec/vo_rec/
├── MainActivity.kt              # 메서드 채널 핸들러
└── LocationTrackingService.kt   # GPS 트래킹 포그라운드 서비스
```

---

## 3. 레이어 구조

```
┌─────────────────────────────────┐
│        Presentation Layer        │
│  (Screens, Widgets, Providers)   │
└──────────────┬──────────────────┘
               │
┌──────────────▼──────────────────┐
│         Domain Layer             │
│  (Models, Repository Interface)  │
└──────────────┬──────────────────┘
               │
┌──────────────▼──────────────────┐
│          Data Layer              │
│  (Repository Impl, Service Impl) │
└─────────────────────────────────┘
```

- Presentation → Domain (인터페이스 호출)
- Data → Domain (인터페이스 구현)
- Riverpod Provider가 Data 구현체를 주입

---

## 4. 데이터 모델

### MemoEntry

```dart
class MemoEntry {
  final DateTime timestamp;
  final double? latitude;
  final double? longitude;
  final String? text;
  final String? photoPath;  // 절대 경로 (MediaStore 저장 결과)
  final String? videoPath;  // 절대 경로 (앱 전용 외부 저장소)
  final double? fishLength; // 물고기 길이 (cm)
  // photoPath와 videoPath는 동시에 존재할 수 없음 (UI에서 마지막 선택으로 대체)
}
```

### LocationStatus

```dart
class LocationStatus {
  final DateTime timestamp;
  final double? latitude;
  final double? longitude;
  final String? address;       // 역지오코딩 주소
  final double? temperature;   // 기온 (°C)
  final String? tideName;      // 물때 이름 (예: "5물")
  final String? tideTime;      // 다음 조시 (예: "만조 18:03")
  final double? waterTemp;     // 수온 (°C)
  final String? stationName;   // 관측소 이름
  final double? stationDistance; // 관측소 거리 (km)
  final bool isMove;           // 이동으로 추가된 현황 블록 여부
}
```

### AppSettings

```dart
class AppSettings {
  final String savePath;       // 메모(.md) 저장 경로
  final String photoSavePath;  // 사진 저장 경로 (기본: DCIM/vo_rec)
  final bool showLocationButton;
  final String? khoaApiKey;    // 해양조사원 API 키 (null이면 기본 키 사용)
}
```

---

## 5. 파일 I/O 전략

### 저장 경로 구조

```
[savePath]/
├── 2026-06-03.md
├── 2026-06-02.md
└── ...

[photoSavePath]/                    # 기본: DCIM/nakkda (갤러리 표시)
├── NAKKDA_20260603_143000.jpg
└── ...

Android/data/com.nakkda.nakkda/files/videos/   # 동영상 전용 (앱 전용 외부 저장소)
├── video_1717394400000.mp4
├── gallery_video_1717394500000.mp4
└── ...
```

### .md 파일 포맷

```markdown
# 2026-06-03

## 현황 (14:30 이동)
- 📍 경남 통영시 미수동
- 🌡 기온: 22.5°C | 🌊 5물 (만조 18:03) | 💧 수온 19.6°C
- 관측소: 통영 (12.3km)

---

### 14:35 | 🛰 34.8540, 128.4330
메모 텍스트

---

### 14:52 | 🛰 34.8540, 128.4330
![](/storage/emulated/0/DCIM/nakkda/NAKKDA_20260603_145200.jpg)
- 📏 38.5cm

---

### 15:10 | 🛰 34.8540, 128.4330
[video](/storage/emulated/0/Android/data/com.nakkda.nakkda/files/videos/video_1717395000000.mp4)
```

**미디어 경로 규칙:**
- 사진: `![](절대경로)` → DCIM/nakkda 또는 savePath/photos/
- 동영상: `[video](절대경로)` → 앱 전용 외부 저장소 videos/ 폴더

### 사진 저장 흐름 (Android 10+)

```
image_picker → 임시 파일 경로
    └─→ saveToGallery(tempPath, relativePath) [Kotlin 메서드 채널]
            └─→ MediaStore.Images.Media.insert()
                    └─→ ContentValues(RELATIVE_PATH = "DCIM/vo_rec")
                            └─→ 갤러리 즉시 반영
                                    └─→ 절대 경로 반환 → MemoEntry.photoPath
```

`MANAGE_EXTERNAL_STORAGE` 권한 불필요. MediaStore API가 직접 공용 DCIM에 쓴다.

### GPS fallback 전략

사진 저장 및 메모 작성 시 GPS 획득 순서:

```
1. locationProvider 현재 AsyncValue
2. locationServiceImpl._cache (마지막 성공 위치)
3. Geolocator.getLastKnownPosition() (OS 레벨 최근 위치)
```

---

## 6. 지도 클러스터링

`map_screen.dart`에서 순수 Dart로 구현한 greedy 클러스터링:

```dart
// 줌 레벨에 따른 클러스터 반경 (도 단위)
double _thresholdDeg() => 0.0003 * math.pow(2.0, 15.0 - _zoom);
// zoom 15 → ~33m, zoom 12 → ~267m
```

- `onPositionChanged`에서 줌 변화량 ≥ 0.5 일 때 재계산
- 단일 지점: 기존 마커 스타일 유지
- 클러스터: 주황 원 + 개수, 탭 시 해당 bounds로 `fitCamera`

---

## 7. 음성 입력 상태 흐름

```
idle ──[탭]──→ listening ──[결과]──→ idle (lastResult 업데이트)
                   │                         │
               [오류]                    ref.listen
                   ↓                         ↓
                error              텍스트 필드에 append
```

- `interimResult`: 실시간 미리보기 (텍스트 필드 미반영)
- `lastResult`: 최종 확정 결과 (텍스트 필드에 append 후 clearResult)
- `pauseFor: 3초` 침묵 후 자동 종료

---

## 8. Riverpod Provider 의존 그래프

```
settingsProvider ← SettingsRepositoryImpl
locationProvider ← LocationServiceImpl
locationProvider ← settingsProvider

todayFileProvider ← MemoRepositoryImpl
todayFileProvider ← settingsProvider

photoProvider ← PhotoServiceImpl (pickImage only)
photoProvider ← todayFileProvider
photoProvider ← settingsProvider
photoProvider ← locationProvider      # GPS fallback
photoProvider ── saveToGallery()      # Kotlin 채널

voiceInputProvider ← speech_to_text

fileListProvider ← FileListRepositoryImpl
fileListProvider ← settingsProvider

permissionStatusProvider ← permission_handler

backupProvider ← DriveBackupService
backupProvider ← settingsProvider
backupProvider ← connectivity_plus
DriveBackupService ← google_sign_in
DriveBackupService ← googleapis (Drive v3)
```

---

## 9. Android 네이티브 채널

`com.vorec.vo_rec/media` 채널 (MainActivity.kt):

| 메서드 | 파라미터 | 반환 | 설명 |
|--------|---------|------|------|
| `saveToGallery` | `path: String`, `relativePath: String` | `String?` (절대 경로) | MediaStore로 공용 폴더에 사진 저장 |
| `pickGalleryImage` | — | `{path, lat, lng}?` | 기존 이미지 전용 갤러리 피커 (ACTION_PICK) |
| `pickGalleryMedia` | `mimeFilter: String` | `{path, isVideo, lat, lng}?` | 이미지·동영상 통합 피커 (ACTION_GET_CONTENT) |
| `scanPhotosByDate` | `year, month, day` | `List<{contentUri, dateTaken, lat, lng}>` | 날짜별 사진 목록 (지도 화면용) |
| `copyContentUriToCache` | `uri: String` | `String?` | content URI → 앱 캐시 복사 |
| `writePhotoBytes` | `bytes: ByteArray`, `filename: String`, `relativePath: String` | `String?` (절대 경로) | Drive 복원 시 미디어 바이트를 MediaStore에 저장 |
| `getAndClearTrackPoints` | — | `List<String>` | GPS 트래킹 포인트 읽기·지우기 (synchronized) |

---

## 10. Google Drive 백업 시스템

### 개요

`features/backup/` 피처 아래 구현된 Google Drive 백업/복원 기능.
Google 로그인(OAuth 2.0) 후 앱 전용 Drive 폴더(`appDataFolder`)에 .md 파일 및 미디어를 저장한다.

### 파일 구조 (Drive)

```
appDataFolder/
├── 2026-06-03.md
├── 2026-06-02.md
├── NAKKDA_20260603_143000.jpg
└── video_1717394400000.mp4
```

### 업로드 스킵 로직

로컬 `SharedPreferences`에 `backup_md_manifest` 키로 `{filename: utf8_byte_length}` 매핑을 저장.
업로드 전 로컬 파일의 UTF-8 바이트 수를 manifest 값과 비교 → 동일하면 스킵.
업로드 성공 시에만 manifest 갱신.

> Drive API `files.list` 의 `size` 필드가 일부 파일에서 null을 반환하는 문제로 로컬 manifest 방식 채택.

### 복원 병합 로직 (`_mergeContent`)

로컬과 Drive 양쪽에 같은 날짜 파일이 있을 때:
1. 각 파일의 블록을 파싱하여 타임스탬프 기준 중복 제거 후 병합
2. 각 파일의 트래킹 포인트(`## 이동 경로` 섹션)도 파싱하여 타임스탬프 기준 병합
3. `MdSerializer.buildFullContent(date, blocks, mergedTrackPoints)` 로 최종 파일 생성

### 병렬 처리

`Future.wait()` 로 4개씩 묶어 병렬 업로드/복원.

---

## 11. GPS 트래킹 동기화 (Android)

`LocationTrackingService.kt`의 `savePoint()`와 `MainActivity.kt`의 `getAndClearTrackPoints` 핸들러는
같은 SharedPreferences 키(`pending_track_points`)를 서로 다른 스레드에서 접근한다.

경쟁 조건 방지:
- `companion object { @JvmField val pendingLock = Any() }` 를 공유 락으로 사용
- 양쪽 모두 `synchronized(pendingLock)` 블록 안에서 읽기→수정→쓰기 수행
- `apply()` → `commit()` 변경 (동기 쓰기로 즉각 반영)

---

## 12. 빌드 플래그

```bash
# 릴리즈 빌드 (V: 드라이브는 한글 경로 우회용 SUBST 가상 드라이브)
V:
flutter build apk --release --no-tree-shake-icons
```

`--no-tree-shake-icons`: `photo_manager` 등 패키지 변동 시 아이콘 트리쉐이킹으로 MaterialIcons가
99% 제거되는 현상이 발생한 이력이 있음. 안전을 위해 항상 비활성화.

`subst V: "D:\개인\dev\vo-rec\vo_rec"`: Flutter AOT 컴파일러가 한글 경로를 처리하지 못하는 문제 우회.

---

## 13. 권한 모델 (Android 13+)

| Flutter 권한 | Android 권한 | 용도 |
|---|---|---|
| `Permission.microphone` | `RECORD_AUDIO` | 음성 메모 |
| `Permission.locationWhenInUse` | `ACCESS_FINE_LOCATION` | GPS 기록 |
| `Permission.camera` | `CAMERA` | 카메라 촬영 |
| `Permission.photos` | `READ_MEDIA_IMAGES` | 갤러리 이미지 |
| `Permission.videos` | `READ_MEDIA_VIDEO` | 갤러리 동영상 |
| `Permission.notification` | `POST_NOTIFICATIONS` | 서비스 알림 |

`photo_manager`가 `PermissionState.authorized`가 되려면 `READ_MEDIA_IMAGES` **와** `READ_MEDIA_VIDEO` 모두 필요.
두 권한은 Android 시스템에서 단일 다이얼로그로 함께 처리된다.
