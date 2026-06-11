# 기능 상세

## 1. 홈 화면

오늘 날짜의 메모 파일을 표시하는 메인 화면입니다.

- 상단 현황 카드: GPS 주소, 기온, 수온, 물때 정보 실시간 표시
- 우측 하단 FAB: 메모 추가 (텍스트 / 음성)
- 사진 아이콘: 일반 카메라 / AR 카메라 / 갤러리 선택 메뉴
- 메모 카드 길게 누르기: 삭제 확인 다이얼로그
- 메모 카드 탭: 수정 시트 표시

---

## 2. 음성 메모

### 인앱 음성 입력

메모 입력 시트의 마이크 버튼으로 `speech_to_text`를 통해 실시간 음성 인식.

### 볼륨 버튼 트리거 (화면 꺼진 상태)

`VoiceRecordForegroundService` 가 백그라운드에서 동작합니다.

| 동작 | 결과 |
|------|------|
| 볼륨 감소 버튼 1회 | 음성 인식 시작 (SpeechRecognizer) |
| 볼륨 감소 버튼 연속 2회 | 인식 취소 |

인식 완료 후 결과 텍스트는 브로드캐스트 → Flutter → 홈 화면의 메모에 자동 저장됩니다.

> 앱 첫 실행 후 마이크 권한 허용 시 서비스가 자동 시작됩니다.

---

## 3. 사진 촬영

### 일반 카메라 (줄자 모드)

화면에 줄자 오버레이가 없는 일반 카메라입니다.

- 핀치 줌 (두 손가락 벌리기/오므리기)
- 탭 초점 조정
- 우측 중앙 워터마크 토글 버튼
- 촬영 후 물고기 길이 입력 시트 표시

### AR 카메라 (실측 모드)

ARCore를 이용한 실제 거리 측정 카메라입니다.

1. 카메라를 평평한 바닥에 향함 → 평면 감지
2. 머리 끝 터치 → 꼬리 끝 터치
3. 두 점 사이 3D 거리를 cm 단위로 표시
4. 촬영 버튼 → 측정선·수치가 합성된 사진 저장

토글 옵션:
- 워터마크 표시 ON/OFF
- 측정 결과 포함 저장 ON/OFF

---

## 4. 워터마크

`lib/features/settings/presentation/watermark_settings_screen.dart` 에서 설정합니다.

| 설정 항목 | 옵션 |
|-----------|------|
| 활성화 | ON / OFF |
| 위치 | 좌상단 / 우상단 / 좌하단 / 우하단 |
| 정렬 | 좌 / 중앙 / 우 |
| 텍스트 라인 | 날짜 / 시간 / 커스텀 텍스트 (최대 3줄) |
| 날짜 형식 | yyyy-MM-dd / yy/MM/dd / MM/dd |
| 시간 형식 | HH:mm / HH:mm:ss / 없음 |
| 폰트 | sans-serif / serif / monospace |
| 폰트 크기 | 슬라이더 (12~64) |
| 굵게 | ON / OFF |
| 박스 투명도 | 슬라이더 (0~1) |

워터마크는 `applyWatermark()` 함수에서 실제 사진 픽셀에 합성됩니다.

---

## 5. GPS 및 위치 정보

### 자동 GPS 첨부

메모 생성 시 현재 위치를 자동으로 첨부합니다.

우선순위:
1. `locationProvider` 실시간 위치
2. `locationProvider.cached` 캐시된 위치
3. `Geolocator.getLastKnownPosition()` 최근 위치

### 현황 블록

홈 화면 상단 카드에 다음 정보가 표시됩니다:

- **📍 주소**: 역지오코딩 (geocoding 패키지)
- **🌡 기온**: 기상청 초단기실황 API
- **💧 수온**: 국립해양조사원 수온 API
- **관측소**: 가장 가까운 조위관측소 (tide_station_data.dart)
- **🌊 물때**: 조위 데이터 기반 밀물/썰물 계산

"현황 기록" 버튼으로 현황 블록을 메모 파일에 삽입할 수 있습니다.

---

## 6. 지도

`flutter_map` 기반 지도 화면에서 GPS가 첨부된 모든 메모를 마커로 표시합니다.

- 메모 파일 전체 스캔 → GPS 좌표 추출
- `CameraFit.bounds`로 모든 마커가 보이도록 초기 뷰 설정
- 단일 좌표일 경우 줌 레벨 15로 중앙 표시
- 마커 탭 → 해당 메모 파일 열기

---

## 7. 파일 목록

날짜별로 저장된 메모 파일(`.md`) 목록을 표시합니다.

- 파일명 (날짜), 첫 번째 항목 텍스트 미리보기, 항목 수 표시
- 탭 → `FileViewerScreen`에서 메모 내용 표시
- 메모 파일 내 사진 탭 → 전체 화면 뷰어 (InteractiveViewer)

---

## 8. 설정

| 설정 | 설명 |
|------|------|
| 메모 저장 경로 | 텍스트 메모 파일(.md) 저장 위치 |
| 사진 저장 경로 | 촬영 사진 저장 위치 (기본: DCIM/nakkda) |
| 위치 버튼 표시 | 홈 화면 위치 정보 버튼 ON/OFF |
| 음성 자동 저장 | 음성 인식 완료 시 자동 저장 ON/OFF |
| KHOA API 키 | 국립해양조사원 API 키 직접 입력 |
| 워터마크 설정 | 상세 워터마크 설정 화면으로 이동 |
| 전체 파일 접근 권한 | DCIM 폴더 직접 접근 권한 요청 |

---

## 9. 권한 체계

| 권한 | Flutter | 필수/선택 | 용도 |
|------|---------|-----------|------|
| `RECORD_AUDIO` | `Permission.microphone` | 필수 | 음성 메모, Foreground Service |
| `ACCESS_FINE_LOCATION` | `Permission.locationWhenInUse` | 필수 | GPS 좌표 기록 |
| `CAMERA` | `Permission.camera` | 필수 | 사진 촬영 |
| `READ_MEDIA_IMAGES` | `Permission.photos` | 필수 | 갤러리 사진 선택 |
| `READ_MEDIA_VIDEO` | `Permission.videos` | 필수 | 갤러리 동영상 선택 |
| `POST_NOTIFICATIONS` | `Permission.notification` | 필수 | 서비스 알림 |

> Android 13+에서 `photo_manager`가 `PermissionState.authorized` 상태가 되려면 `READ_MEDIA_IMAGES`와 `READ_MEDIA_VIDEO` 모두 필요합니다.
