# vo-rec

낚시·야외 활동 중 현재 위치, 환경 정보(기온·물때·수온)와 함께 메모를 빠르게 남길 수 있는 Android 현장 기록 앱.

---

## 주요 기능

| 기능 | 설명 |
|------|------|
| **음성 메모** | 탭 → 음성 인식 시작, 3초 침묵 후 자동 종료. 말하는 동안 실시간 미리보기 표시 |
| **사진 첨부** | 카메라 촬영 또는 갤러리 선택 → DCIM/nakkda에 저장, 갤러리 즉시 반영 |
| **동영상 촬영·첨부** | 카메라 스와이프로 동영상 모드 전환, 720p/1080p 해상도 선택. 갤러리에서도 선택 가능. 메모에 썸네일로 표시, 탭 시 전체화면 재생 |
| **GPS 자동 삽입** | 메모·사진 저장 시 현재 GPS 좌표 자동 기록 (캐시 → 최근 위치 순 fallback) |
| **위치 추가** | 현재 위치·기온·물때·수온을 수집해 미리보기 후 저장 |
| **지도 보기** | 날짜별 GPS 지점 지도 표시, 경로 연결, 줌 연동 자동 클러스터링 |
| **날짜별 .md 저장** | 모든 메모를 `YYYY-MM-DD.md` 파일 하나에 통합 저장 |
| **환경 정보 자동 입력** | GPS 기반 역지오코딩 주소, 기온(기상청), 물때·수온(해양조사원 API) |

---

## 스크린샷 구성

```
권한 요청 → 메인(홈) → 메모 입력 시트
                     → 소스 선택 시트 → 카메라 (사진/동영상 모드)
                                      → 갤러리 피커 (전체/사진/동영상 탭)
                     → 위치 추가 미리보기
                     → 지도
                     → 파일 목록 → 파일 뷰어
                     → 설정
```

---

## 기술 스택

| 항목 | 내용 |
|------|------|
| 플랫폼 | Android (Flutter) |
| 최소 SDK | API 26 (Android 8.0) |
| 상태 관리 | flutter_riverpod ^2.x |
| 라우팅 | go_router ^14.x |
| 지도 | flutter_map ^7.x + latlong2 |
| 음성 인식 | speech_to_text ^7.x (디바이스 내장 엔진) |
| 사진 | camera ^0.11.x + MediaStore API (Kotlin 채널) |
| 동영상 | video_player ^2.9.x + video_thumbnail ^0.5.x |
| 갤러리 피커 | photo_manager ^3.4.x (커스텀 갤러리, 탭 필터링) |
| GPS | geolocator ^13.x |
| 권한 | permission_handler ^11.x |
| 저장소 | path_provider + shared_preferences |
| HTTP | http ^1.x (기상청·해양조사원 API) |

---

## 저장 구조

```
[메모 저장 경로]/
├── 2026-06-03.md
├── 2026-06-02.md
└── ...

DCIM/nakkda/                          # 사진 (갤러리에 표시)
└── NAKKDA_20260603_143000.jpg

Android/data/com.nakkda.nakkda/files/videos/   # 동영상 (앱 전용)
├── video_1717394400000.mp4
└── gallery_video_1717394500000.mp4
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
감성돔 노림. 조류 약하고 바람 없음.

---

### 14:52 | 🛰 34.8540, 128.4330
![](/storage/emulated/0/DCIM/nakkda/NAKKDA_20260603_145200.jpg)
- 📏 38.5cm

---

### 15:10 | 🛰 34.8540, 128.4330
[video](/storage/emulated/0/Android/data/com.nakkda.nakkda/files/videos/video_1717395000000.mp4)
```

---

## 빌드 및 실행

```bash
cd vo_rec
flutter pub get
flutter run
```

APK 빌드:
```bash
flutter build apk --debug
# 한글 경로 기기에 설치:
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

앱 아이콘 재생성:
```bash
flutter pub run flutter_launcher_icons
```

---

## 문서

| 문서 | 설명 |
|------|------|
| [docs/prd.md](docs/prd.md) | 제품 요구사항 정의서 |
| [docs/architecture.md](docs/architecture.md) | 아키텍처 설계서 |
| [docs/screens.md](docs/screens.md) | 화면 설계서 |

---

## 권한

| 권한 | 용도 |
|------|------|
| `RECORD_AUDIO` | 음성 메모 녹음, 동영상 오디오 녹음 |
| `ACCESS_FINE_LOCATION` | GPS 좌표 기록 |
| `CAMERA` | 사진 촬영 및 동영상 녹화 |
| `READ_MEDIA_IMAGES` | 갤러리 사진 접근 |
| `READ_MEDIA_VIDEO` | 갤러리 동영상 접근 |
| `READ_MEDIA_VISUAL_USER_SELECTED` | Android 14+ 부분 접근 모드 지원 |
| `ACCESS_MEDIA_LOCATION` | 갤러리 사진 EXIF GPS 읽기 |
