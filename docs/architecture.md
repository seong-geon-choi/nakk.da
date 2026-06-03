# 아키텍처

## 전체 구조

낚.다는 Flutter + Kotlin 하이브리드 앱으로, Flutter UI 레이어와 Android Native 레이어가 MethodChannel로 통신합니다.

```
┌─────────────────────────────────────────────────────┐
│                  Flutter UI Layer                   │
│  (Riverpod 상태관리 / go_router 라우팅 / Material 3)  │
├─────────────────────────────────────────────────────┤
│              MethodChannel Bridge                   │
│  com.nakkda.nakkda/media   →  MediaStore 저장        │
│  com.nakkda.nakkda/ar      →  AR 카메라 실행          │
│  com.nakkda.nakkda/accessibility → 음성 서비스        │
├─────────────────────────────────────────────────────┤
│               Android Native Layer                  │
│  MainActivity  ArMeasureActivity  ForegroundService │
└─────────────────────────────────────────────────────┘
```

---

## Flutter 레이어

### 상태 관리 — Riverpod

`AsyncNotifierProvider` 패턴을 사용합니다. 각 기능별 Provider가 독립적으로 상태를 관리합니다.

```
settingsProvider         → AppSettings (저장 경로, 워터마크 설정)
todayFileProvider        → 오늘 메모 파일 (CRUD)
dayFileProvider(path)    → 특정 날짜 메모 파일 (CRUD)
photoProvider            → 사진 저장 (pickAndSave / saveFromPath)
locationProvider         → GPS + 날씨 + 물때 현황
voiceInputProvider       → 음성 인식 상태
permissionStatusProvider → 앱 권한 상태
```

### 라우팅 — go_router

```
/                → PermissionGate (최초 실행 권한 확인)
/home            → HomeScreen (오늘 메모)
/files           → FileListScreen (날짜별 목록)
/files/:path     → FileViewerScreen (메모 뷰어)
/map             → MapScreen (지도)
/settings        → SettingsScreen
/settings/watermark → WatermarkSettingsScreen
```

### 메모 직렬화

메모는 마크다운(`.md`) 형식으로 파일 시스템에 저장됩니다. `MdSerializer`가 직렬화/역직렬화를 담당합니다.

```
블록 타입:
  LocationStatus  → ## 현황 블록 (날씨/물때)
  MemoEntry       → ### HH:mm 블록 (텍스트/사진)
```

---

## Android Native 레이어

### MainActivity

Flutter와 네이티브 기능을 연결하는 허브 역할.

- **`/media` 채널**: `saveToGallery()` — MediaStore API로 사진 저장, 파일명 `NAKKDA_yyyyMMdd_HHmmss.jpg` 생성, `MediaScannerConnection.scanFile()` 호출로 갤러리 즉시 반영
- **`/ar` 채널**: `launchArMeasure()` — `ArMeasureActivity`를 `startActivityForResult`로 실행
- **`/accessibility` 채널**: 음성 서비스 상태 조회 및 결과 수신

### ArMeasureActivity

ARCore 기반 실측 카메라. OpenGL GLSurfaceView 위에 Flutter 없이 순수 Kotlin UI로 구성.

```
GLSurfaceView (ARCore 배경 렌더링)
  └── ArDotsOverlayView (터치 → 측정 점 표시)
      └── 상태 텍스트 / 거리 카드 / 셔터 버튼 / 토글 버튼
```

측정 흐름:
1. ARCore `HitTest` → 평면 위 3D 좌표 획득
2. 두 점 사이 유클리드 거리 계산 (미터 → cm)
3. `PixelCopy`로 GLSurface 캡처 → 측정선·수치 합성 → JPEG 저장
4. `setResult(RESULT_OK)` → Flutter로 반환

### VoiceRecordForegroundService

화면 꺼진 상태에서도 볼륨 버튼으로 음성 메모를 시작하는 서비스.

- `PARTIAL_WAKE_LOCK`으로 CPU 유지
- `ACTION_VOLUME_CHANGED` 브로드캐스트 수신 (볼륨 값 변화 감지)
- 볼륨 단일 감소 → `SpeechRecognizer` 시작
- 볼륨 연속 감소 (더블 클릭) → 인식 취소
- 결과 → `AccessibilityService`의 SharedPreferences에 저장 → Flutter에 브로드캐스트 전달

---

## 데이터 흐름 — 사진 촬영

```
사용자 촬영
    │
    ├─ 일반 카메라 (CameraRulerScreen)
    │      camera 패키지 takePicture()
    │      applyWatermark() → 임시 JPEG
    │      _LengthInputSheet → 길이 입력
    │      saveToGallery() [MethodChannel]
    │
    ├─ AR 카메라 (ArMeasureActivity)
    │      ARCore HitTest × 2
    │      PixelCopy → 측정선 합성
    │      applyWatermark() (Flutter 측)
    │      saveToGallery() [MethodChannel]
    │
    └─ 갤러리 (image_picker)
           pickImage()
           saveToGallery() [MethodChannel]

saveToGallery (Kotlin)
    ContentResolver.insert(MediaStore)
    openOutputStream() → 파일 복사
    IS_PENDING = 0
    MediaScannerConnection.scanFile()
    → 반환: /storage/emulated/0/DCIM/nakkda/NAKKDA_xxx.jpg

MemoEntry { photoPath: 반환된_절대경로 }
    → MdSerializer.serializeEntry()
    → .md 파일에 저장
```

---

## 저장 경로 전략

| 조건 | 메모 저장 경로 | 사진 저장 경로 |
|------|--------------|--------------|
| MANAGE_EXTERNAL_STORAGE 허가 | `DCIM/nakkda/` | `DCIM/nakkda/` |
| 미허가 | 앱 전용 외부 저장소 | `DCIM/nakkda/` (MediaStore) |
| 외부 저장소 없음 | 앱 내부 저장소 | 앱 내부 저장소 |

> 사진은 항상 MediaStore를 통해 저장되므로 MANAGE_EXTERNAL_STORAGE 없이도 DCIM/nakkda 경로에 저장 가능합니다.
