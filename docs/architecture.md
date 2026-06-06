# 아키텍처 설계서: vo-rec

**버전:** 2.1  
**최초 작성:** 2026-06-02  
**최종 수정:** 2026-06-06  
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
└── MainActivity.kt   # saveToGallery (MediaStore), scanFile 메서드 채널
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
