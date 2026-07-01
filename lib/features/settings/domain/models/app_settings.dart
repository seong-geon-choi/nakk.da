import '../../../../core/constants/api_keys.dart';
import '../../../../core/constants/app_constants.dart';

// ── 워터마크 열거형 ────────────────────────────────────────────

enum WatermarkPosition { topLeft, topRight, bottomLeft, bottomRight }
enum WatermarkLineType { date, time, customText, customText2 }
enum WatermarkAlign { left, center, right }
enum WatermarkFont { sansSerif, monospace, serif, heavy }
enum WatermarkWeight { normal, bold, black }

// ── 워터마크 박스 (날짜/시간/커스텀 각각 독립 설정·위치) ─────────

class WatermarkBox {
  final WatermarkLineType type;
  final bool visible;
  final String customText;
  final double dx; // 컨테이너 내 상대 위치 (사진 shortSide 기준 정규화 오프셋)
  final double dy;
  final double fontSize;
  final WatermarkWeight weight;
  final WatermarkFont fontFamily;
  final int textColor; // ARGB 정수 (기본 흰색)
  final WatermarkAlign alignment;
  final String dateFormat; // type == date 일 때 사용
  final String timeFormat; // type == time 일 때 사용

  const WatermarkBox({
    required this.type,
    this.visible = true,
    this.customText = '',
    this.dx = 0,
    this.dy = 0,
    this.fontSize = 32,
    this.weight = WatermarkWeight.normal,
    this.fontFamily = WatermarkFont.sansSerif,
    this.textColor = 0xFFFFFFFF,
    this.alignment = WatermarkAlign.left,
    this.dateFormat = 'yyyy-MM-dd',
    this.timeFormat = 'HH:mm',
  });

  WatermarkBox copyWith({
    bool? visible,
    String? customText,
    double? dx,
    double? dy,
    double? fontSize,
    WatermarkWeight? weight,
    WatermarkFont? fontFamily,
    int? textColor,
    WatermarkAlign? alignment,
    String? dateFormat,
    String? timeFormat,
  }) =>
      WatermarkBox(
        type: type,
        visible: visible ?? this.visible,
        customText: customText ?? this.customText,
        dx: dx ?? this.dx,
        dy: dy ?? this.dy,
        fontSize: fontSize ?? this.fontSize,
        weight: weight ?? this.weight,
        fontFamily: fontFamily ?? this.fontFamily,
        textColor: textColor ?? this.textColor,
        alignment: alignment ?? this.alignment,
        dateFormat: dateFormat ?? this.dateFormat,
        timeFormat: timeFormat ?? this.timeFormat,
      );

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'visible': visible,
        'customText': customText,
        'dx': dx,
        'dy': dy,
        'fontSize': fontSize,
        'weight': weight.name,
        'fontFamily': fontFamily.name,
        'textColor': textColor,
        'alignment': alignment.name,
        'dateFormat': dateFormat,
        'timeFormat': timeFormat,
      };

  factory WatermarkBox.fromJson(Map<String, dynamic> j) => WatermarkBox(
        type: WatermarkLineType.values.byName(j['type'] as String? ?? 'date'),
        visible: j['visible'] as bool? ?? true,
        customText: j['customText'] as String? ?? '',
        dx: (j['dx'] as num?)?.toDouble() ?? 0,
        dy: (j['dy'] as num?)?.toDouble() ?? 0,
        fontSize: (j['fontSize'] as num?)?.toDouble() ?? 32,
        weight:
            WatermarkWeight.values.byName(j['weight'] as String? ?? 'normal'),
        fontFamily:
            WatermarkFont.values.byName(j['fontFamily'] as String? ?? 'sansSerif'),
        textColor: (j['textColor'] as num?)?.toInt() ?? 0xFFFFFFFF,
        alignment:
            WatermarkAlign.values.byName(j['alignment'] as String? ?? 'left'),
        dateFormat: j['dateFormat'] as String? ?? 'yyyy-MM-dd',
        timeFormat: j['timeFormat'] as String? ?? 'HH:mm',
      );
}

// ── 워터마크 전체 설정 ─────────────────────────────────────────

class WatermarkSettings {
  final bool enabled;
  final List<WatermarkBox> boxes;
  final double containerPosX; // 0(좌)~1(우) 컨테이너 전체 위치
  final double containerPosY; // 0(상)~1(하)
  final int bgColorIndex;     // bgPresets 인덱스
  final double bgOpacity;     // 0 ~ 1
  final bool hideContainerBorder; // 카메라 라이브 화면의 드래그 안내 테두리 숨김
  final List<int> customColors;   // 컬러피커로 선택한 사용자 색상 히스토리(최신순)

  /// 컨테이너 배경 프리셋 색상 (불투명 ARGB 기준)
  static const List<int> bgPresets = [
    0xFF000000, // 검정
    0xFF424242, // 진회색
    0xFFFFFFFF, // 흰색
    0xFF0D47A1, // 남색
    0xFF1B5E20, // 초록
    0xFFB71C1C, // 빨강
  ];

  /// 글자색 기본 프리셋 (박스별 선택). 그 외 색은 컬러피커로 선택.
  static const List<int> textPresets = [
    0xFFFFFFFF, // 흰색
    0xFF000000, // 검정
    0xFFFFEB3B, // 노랑
    0xFFF44336, // 빨강
    0xFF2196F3, // 파랑
  ];

  /// 컬러피커로 선택한 사용자 색상 히스토리 최대 개수
  static const int maxCustomColors = 5;

  /// 기본 박스 4종. 설치 시 기본 레이아웃(개발 기기에서 구성한 값을 기본값으로 채택).
  static List<WatermarkBox> defaultBoxes() => const [
        WatermarkBox(
          type: WatermarkLineType.date,
          dx: 0.14778951319252573,
          dy: 0.19443800019054883,
          fontSize: 24,
          weight: WatermarkWeight.normal,
          fontFamily: WatermarkFont.sansSerif,
          textColor: 0xFFFFFFFF,
        ),
        WatermarkBox(
          type: WatermarkLineType.time,
          dx: -0.3018272679026534,
          dy: 0.09612376143292686,
          fontSize: 76,
          weight: WatermarkWeight.black,
          fontFamily: WatermarkFont.heavy,
          textColor: 0xFFFFFFFF,
        ),
        WatermarkBox(
          type: WatermarkLineType.customText,
          customText: '낚.다',
          dx: 0.3153880049542683,
          dy: 0.1383987947789635,
          fontSize: 20,
          weight: WatermarkWeight.black,
          fontFamily: WatermarkFont.sansSerif,
          textColor: 0xFFFFEB3B,
        ),
        WatermarkBox(
            type: WatermarkLineType.customText2, visible: false, dy: 0.36),
      ];

  /// 4코너 enum → (posX, posY) 변환 (구 설정 마이그레이션용)
  static (double, double) posFromCorner(WatermarkPosition p) => switch (p) {
        WatermarkPosition.topLeft => (0.0, 0.0),
        WatermarkPosition.topRight => (1.0, 0.0),
        WatermarkPosition.bottomLeft => (0.0, 1.0),
        WatermarkPosition.bottomRight => (1.0, 1.0),
      };

  WatermarkSettings({
    this.enabled = false,
    List<WatermarkBox>? boxes,
    this.containerPosX = 0.6980602179600072,
    this.containerPosY = 0.7945379171746418,
    this.bgColorIndex = 0,
    this.bgOpacity = 0.0,
    this.hideContainerBorder = true,
    this.customColors = const [],
  }) : boxes = boxes ?? defaultBoxes();

  /// 컨테이너 배경색 (투명도 적용 ARGB)
  int get bgColorArgb {
    final base = bgPresets[bgColorIndex.clamp(0, bgPresets.length - 1)];
    final a = (bgOpacity * 255).round().clamp(0, 255);
    return (a << 24) | (base & 0x00FFFFFF);
  }

  WatermarkSettings copyWith({
    bool? enabled,
    List<WatermarkBox>? boxes,
    double? containerPosX,
    double? containerPosY,
    int? bgColorIndex,
    double? bgOpacity,
    bool? hideContainerBorder,
    List<int>? customColors,
  }) =>
      WatermarkSettings(
        enabled: enabled ?? this.enabled,
        boxes: boxes ?? this.boxes,
        containerPosX: containerPosX ?? this.containerPosX,
        containerPosY: containerPosY ?? this.containerPosY,
        bgColorIndex: bgColorIndex ?? this.bgColorIndex,
        bgOpacity: bgOpacity ?? this.bgOpacity,
        hideContainerBorder: hideContainerBorder ?? this.hideContainerBorder,
        customColors: customColors ?? this.customColors,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'boxes': boxes.map((b) => b.toJson()).toList(),
        'containerPosX': containerPosX,
        'containerPosY': containerPosY,
        'bgColorIndex': bgColorIndex,
        'bgOpacity': bgOpacity,
        'hideContainerBorder': hideContainerBorder,
        'customColors': customColors,
      };

  factory WatermarkSettings.fromJson(Map<String, dynamic> j) {
    // 신 포맷
    if (j['boxes'] != null) {
      final boxes = (j['boxes'] as List<dynamic>)
          .map((b) => WatermarkBox.fromJson(b as Map<String, dynamic>))
          .toList();
      // 구버전 저장본 보강: 누락된 박스 타입(예: 텍스트2)을 비가시로 추가
      var dy = boxes.length * 0.12;
      for (final t in WatermarkLineType.values) {
        if (!boxes.any((b) => b.type == t)) {
          boxes.add(WatermarkBox(type: t, visible: false, dy: dy));
          dy += 0.12;
        }
      }
      return WatermarkSettings(
        enabled: j['enabled'] as bool? ?? false,
        boxes: boxes,
        containerPosX: (j['containerPosX'] as num?)?.toDouble() ?? 1.0,
        containerPosY: (j['containerPosY'] as num?)?.toDouble() ?? 1.0,
        bgColorIndex: (j['bgColorIndex'] as num?)?.toInt() ?? 0,
        bgOpacity: (j['bgOpacity'] as num?)?.toDouble() ?? 0.67,
        hideContainerBorder: j['hideContainerBorder'] as bool? ?? false,
        customColors: (j['customColors'] as List<dynamic>?)
                ?.map((c) => (c as num).toInt())
                .toList() ??
            const [],
      );
    }
    // ── 구 포맷(단일 박스 + lines) → 신 포맷 마이그레이션 ──
    return WatermarkSettings._fromLegacy(j);
  }

  factory WatermarkSettings._fromLegacy(Map<String, dynamic> j) {
    final oldFontSize = (j['fontSize'] as num?)?.toDouble() ?? 32;
    final oldWeight = (j['bold'] as bool? ?? false)
        ? WatermarkWeight.bold
        : WatermarkWeight.normal;
    final oldAlign =
        WatermarkAlign.values.byName(j['alignment'] as String? ?? 'right');
    final oldFont =
        WatermarkFont.values.byName(j['fontFamily'] as String? ?? 'sansSerif');
    final oldDateFmt = j['dateFormat'] as String? ?? 'yyyy-MM-dd';
    final oldTimeFmt = j['timeFormat'] as String? ?? 'HH:mm';

    // 컨테이너 위치: posX/posY 우선, 없으면 코너 enum에서 유도
    final position =
        WatermarkPosition.values.byName(j['position'] as String? ?? 'bottomRight');
    final corner = posFromCorner(position);
    final posX = (j['posX'] as num?)?.toDouble() ?? corner.$1;
    final posY = (j['posY'] as num?)?.toDouble() ?? corner.$2;

    // 구 lines → boxes (등장 순서대로 세로 스택). 누락 타입은 비가시로 보강.
    final byType = <WatermarkLineType, Map<String, dynamic>>{};
    final order = <WatermarkLineType>[];
    final rawLines = j['lines'] as List<dynamic>?;
    if (rawLines != null) {
      for (final l in rawLines) {
        final m = l as Map<String, dynamic>;
        final t = WatermarkLineType.values.byName(m['type'] as String? ?? 'date');
        if (!byType.containsKey(t)) {
          byType[t] = m;
          order.add(t);
        }
      }
    }
    for (final t in WatermarkLineType.values) {
      if (!byType.containsKey(t)) {
        byType[t] = {'type': t.name, 'visible': false, 'customText': ''};
        order.add(t);
      }
    }

    var dy = 0.0;
    final boxes = <WatermarkBox>[];
    for (final t in order) {
      final m = byType[t]!;
      boxes.add(WatermarkBox(
        type: t,
        visible: m['visible'] as bool? ?? true,
        customText: m['customText'] as String? ?? '',
        dx: 0,
        dy: dy,
        fontSize: oldFontSize,
        weight: oldWeight,
        fontFamily: oldFont,
        textColor: 0xFFFFFFFF,
        alignment: oldAlign,
        dateFormat: oldDateFmt,
        timeFormat: oldTimeFmt,
      ));
      dy += 0.12;
    }

    return WatermarkSettings(
      enabled: j['enabled'] as bool? ?? false,
      boxes: boxes,
      containerPosX: posX,
      containerPosY: posY,
      bgColorIndex: 0, // 검정
      bgOpacity: (j['boxOpacity'] as num?)?.toDouble() ?? 0.67,
    );
  }
}

// ── 빠른 메모 실행 모드 ────────────────────────────────────────

enum QuickLaunchMode { none, shake, volume }

// ── 앱 전체 설정 ───────────────────────────────────────────────

/// 출퇴근 알림음 모드
enum CommuteSoundMode { vibrateOnly, vibrateBell, bell, silent, systemDefault }

/// 출퇴근 알림 감시 시간대(지점별 할당)
enum CommuteWindow { am, pm, custom }

/// 메모 입력항목 복잡도
/// - simpleFishing: 현장정보 + 메모(조과 포함)
/// - complexFishing: + 태클 정보, 선사 정보
/// - general: 현장정보 + 메모(어종·길이 제외)
enum MemoComplexity { simpleFishing, complexFishing, general }

/// 태클 프리셋 항목 종류(로드/릴/라인/채비)
enum TackleField { rod, reel, line, rig }

/// 선사 프리셋 항목 종류(선박명/항구/포인트/낚시종류)
enum VesselField { name, port, point, fishType }

/// 출퇴근 알림 지점(지도에서 길게 눌러 지정)
class CommutePin {
  final double lat;
  final double lng;
  final String label;
  final CommuteWindow window; // 이 지점에 할당된 감시 시간대
  const CommutePin({
    required this.lat,
    required this.lng,
    this.label = '',
    this.window = CommuteWindow.am,
  });

  Map<String, dynamic> toJson() =>
      {'lat': lat, 'lng': lng, 'label': label, 'window': window.name};

  factory CommutePin.fromJson(Map<String, dynamic> j) => CommutePin(
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        label: j['label'] as String? ?? '',
        window: CommuteWindow.values.firstWhere(
          (e) => e.name == j['window'],
          orElse: () => CommuteWindow.am,
        ),
      );
}

class AppSettings {
  final String savePath;       // SAF URI (content://) 또는 빈 문자열
  final String saveDisplayPath; // 사람이 읽을 수 있는 경로 (UI 표시용)
  final String photoSavePath;
  final bool showLocationButton;
  final bool autoLocationOnFirstEntry; // 첫 기록 시 현장 정보 1회 자동 추가
  final bool autoSaveVoice;
  final bool showAddressInMemoName;
  final MemoComplexity memoComplexity; // 메모 입력항목 복잡도(단순/복잡/일반)
  final bool shareEnabled; // 메모 공유 버튼 표시 여부 (향후 유료화 대비 토글)
  final bool adsEnabled; // 광고 노출 여부 (개발자 메뉴 토글, 기본 off)
  final String? khoaApiKey;
  final WatermarkSettings watermark;
  final bool showTrackingButton;
  final bool locationTrackingEnabled;
  final int trackingIntervalMeters;
  final QuickLaunchMode quickLaunchMode;
  final double shakeThresholdG; // 흔들기 감지 가속도 임계값(G), 2.5~5.0
  final bool driveBackupEnabled;
  final bool driveBackupIncludeMedia;
  final DateTime? lastSyncAt;
  final bool? lastSyncSuccess;
  final List<String> fishSpecies; // 어종 입력 목록 (사용자 편집 가능)
  final List<String> hiddenFishSpecies; // 메모 드롭다운에서 숨길(체크 해제) 어종
  // 태클 프리셋(입력 시 셀렉트박스로 재사용, 최신순)
  final List<String> tackleRods;
  final List<String> tackleReels;
  final List<String> tackleLines;
  final List<String> tackleRigs;
  // 선사 프리셋
  final List<String> vesselNames;
  final List<String> vesselPorts;
  final List<String> vesselPoints;
  final List<String> vesselFishTypes;
  final double locationFabRight;  // 홈 '환경 추가' FAB 위치 (right)
  final double locationFabBottom; // 홈 '환경 추가' FAB 위치 (bottom)
  final double trackingFabRight;  // 홈 트래킹 FAB 위치 (right)
  final double trackingFabBottom; // 홈 트래킹 FAB 위치 (bottom)
  // ── 지하철 출퇴근 알림 ──────────────────────────────
  final bool commuteAlarmEnabled;
  final int commuteRadius; // 반경(m), 50~2000, 기본 700
  final CommuteSoundMode commuteSoundMode;
  final List<CommutePin> commutePins; // 최대 3개
  final int commuteAmStart; // 출근 창 시작(자정 기준 분), 기본 480(08:00)
  final int commuteAmEnd;   // 출근 창 종료, 기본 540(09:00)
  final int commutePmStart; // 퇴근 창 시작, 기본 1140(19:00)
  final int commutePmEnd;   // 퇴근 창 종료, 기본 1200(20:00)
  final int commuteCustomStart; // 사용자지정 창 시작, 기본 600(10:00)
  final int commuteCustomEnd;   // 사용자지정 창 종료, 기본 720(12:00)
  final bool commuteAmEnabled;     // 출근 시간대 활성
  final bool commutePmEnabled;     // 퇴근 시간대 활성
  final bool commuteCustomEnabled; // 사용자지정 시간대 활성
  final bool commuteWeekdaysOnly; // 평일만 감시
  final bool commuteAlarmActive; // 지도에서 빠르게 켜고/끄는 추적 활성 상태

  bool get needsFolderSetup => savePath.isEmpty;

  /// 실제 추적 동작 여부(마스터 ON + 활성 + 지점 있음)
  bool get commuteTracking =>
      commuteAlarmEnabled && commuteAlarmActive && commutePins.isNotEmpty;

  /// 조과(어종·길이) 입력 표시 여부 — 일반 모드에서만 숨김
  bool get showCatchInput => memoComplexity != MemoComplexity.general;

  /// 태클·선사 등 복잡 항목 표시 여부
  bool get showComplexInput => memoComplexity == MemoComplexity.complexFishing;

  /// 태클 항목별 프리셋 목록
  List<String> tacklePresetsFor(TackleField f) => switch (f) {
        TackleField.rod => tackleRods,
        TackleField.reel => tackleReels,
        TackleField.line => tackleLines,
        TackleField.rig => tackleRigs,
      };

  /// 선사 항목별 프리셋 목록
  List<String> vesselPresetsFor(VesselField f) => switch (f) {
        VesselField.name => vesselNames,
        VesselField.port => vesselPorts,
        VesselField.point => vesselPoints,
        VesselField.fishType => vesselFishTypes,
      };

  /// 메모 작성 드롭다운에 노출할 어종 (숨김 제외).
  /// 주의: 음성/메모 텍스트 어종 탐지는 항상 전체 [fishSpecies]를 사용한다.
  List<String> get visibleFishSpecies =>
      fishSpecies.where((s) => !hiddenFishSpecies.contains(s)).toList();

  AppSettings({
    required this.savePath,
    this.saveDisplayPath = '',
    required this.photoSavePath,
    this.showLocationButton = true,
    this.autoLocationOnFirstEntry = false,
    this.autoSaveVoice = true,
    this.showAddressInMemoName = true,
    this.memoComplexity = MemoComplexity.simpleFishing,
    this.shareEnabled = true,
    this.adsEnabled = false,
    this.khoaApiKey,
    WatermarkSettings? watermark,
    this.showTrackingButton = true,
    this.locationTrackingEnabled = false,
    this.trackingIntervalMeters = 100,
    this.quickLaunchMode = QuickLaunchMode.shake,
    this.shakeThresholdG = 3.5,
    this.driveBackupEnabled = false,
    this.driveBackupIncludeMedia = false,
    this.lastSyncAt,
    this.lastSyncSuccess,
    List<String>? fishSpecies,
    List<String>? hiddenFishSpecies,
    this.locationFabRight = 16,
    this.locationFabBottom = 100,
    this.trackingFabRight = 16,
    this.trackingFabBottom = 172,
    this.commuteAlarmEnabled = false,
    this.commuteRadius = 700,
    this.commuteSoundMode = CommuteSoundMode.systemDefault,
    this.commutePins = const [],
    this.commuteAmStart = 480,
    this.commuteAmEnd = 540,
    this.commutePmStart = 1140,
    this.commutePmEnd = 1200,
    this.commuteCustomStart = 600,
    this.commuteCustomEnd = 720,
    this.commuteAmEnabled = true,
    this.commutePmEnabled = true,
    this.commuteCustomEnabled = false,
    this.commuteWeekdaysOnly = true,
    this.commuteAlarmActive = true,
    this.tackleRods = const [],
    this.tackleReels = const [],
    this.tackleLines = const [],
    this.tackleRigs = const [],
    this.vesselNames = const [],
    this.vesselPorts = const [],
    this.vesselPoints = const [],
    this.vesselFishTypes = const [],
  })  : watermark = watermark ?? WatermarkSettings(),
        fishSpecies = fishSpecies ?? kCommonFishSpecies,
        hiddenFishSpecies = hiddenFishSpecies ?? const [];

  String get effectiveKhoaApiKey {
    final key = khoaApiKey?.trim();
    return (key != null && key.isNotEmpty) ? key : kDefaultKhoaApiKey;
  }

  AppSettings copyWith({
    String? savePath,
    String? saveDisplayPath,
    String? photoSavePath,
    bool? showLocationButton,
    bool? autoLocationOnFirstEntry,
    bool? autoSaveVoice,
    bool? showAddressInMemoName,
    MemoComplexity? memoComplexity,
    bool? shareEnabled,
    bool? adsEnabled,
    String? khoaApiKey,
    bool clearKhoaApiKey = false,
    WatermarkSettings? watermark,
    bool? showTrackingButton,
    bool? locationTrackingEnabled,
    int? trackingIntervalMeters,
    QuickLaunchMode? quickLaunchMode,
    double? shakeThresholdG,
    bool? driveBackupEnabled,
    bool? driveBackupIncludeMedia,
    DateTime? lastSyncAt,
    bool? lastSyncSuccess,
    bool clearLastSync = false,
    List<String>? fishSpecies,
    List<String>? hiddenFishSpecies,
    List<String>? tackleRods,
    List<String>? tackleReels,
    List<String>? tackleLines,
    List<String>? tackleRigs,
    List<String>? vesselNames,
    List<String>? vesselPorts,
    List<String>? vesselPoints,
    List<String>? vesselFishTypes,
    double? locationFabRight,
    double? locationFabBottom,
    double? trackingFabRight,
    double? trackingFabBottom,
    bool? commuteAlarmEnabled,
    int? commuteRadius,
    CommuteSoundMode? commuteSoundMode,
    List<CommutePin>? commutePins,
    int? commuteAmStart,
    int? commuteAmEnd,
    int? commutePmStart,
    int? commutePmEnd,
    int? commuteCustomStart,
    int? commuteCustomEnd,
    bool? commuteAmEnabled,
    bool? commutePmEnabled,
    bool? commuteCustomEnabled,
    bool? commuteWeekdaysOnly,
    bool? commuteAlarmActive,
  }) {
    return AppSettings(
      savePath: savePath ?? this.savePath,
      saveDisplayPath: saveDisplayPath ?? this.saveDisplayPath,
      photoSavePath: photoSavePath ?? this.photoSavePath,
      showLocationButton: showLocationButton ?? this.showLocationButton,
      autoLocationOnFirstEntry:
          autoLocationOnFirstEntry ?? this.autoLocationOnFirstEntry,
      autoSaveVoice: autoSaveVoice ?? this.autoSaveVoice,
      showAddressInMemoName: showAddressInMemoName ?? this.showAddressInMemoName,
      memoComplexity: memoComplexity ?? this.memoComplexity,
      shareEnabled: shareEnabled ?? this.shareEnabled,
      adsEnabled: adsEnabled ?? this.adsEnabled,
      khoaApiKey: clearKhoaApiKey ? null : (khoaApiKey ?? this.khoaApiKey),
      watermark: watermark ?? this.watermark,
      showTrackingButton: showTrackingButton ?? this.showTrackingButton,
      locationTrackingEnabled: locationTrackingEnabled ?? this.locationTrackingEnabled,
      trackingIntervalMeters: trackingIntervalMeters ?? this.trackingIntervalMeters,
      quickLaunchMode: quickLaunchMode ?? this.quickLaunchMode,
      shakeThresholdG: shakeThresholdG ?? this.shakeThresholdG,
      driveBackupEnabled: driveBackupEnabled ?? this.driveBackupEnabled,
      driveBackupIncludeMedia: driveBackupIncludeMedia ?? this.driveBackupIncludeMedia,
      lastSyncAt: clearLastSync ? null : (lastSyncAt ?? this.lastSyncAt),
      lastSyncSuccess: clearLastSync ? null : (lastSyncSuccess ?? this.lastSyncSuccess),
      fishSpecies: fishSpecies ?? this.fishSpecies,
      hiddenFishSpecies: hiddenFishSpecies ?? this.hiddenFishSpecies,
      tackleRods: tackleRods ?? this.tackleRods,
      tackleReels: tackleReels ?? this.tackleReels,
      tackleLines: tackleLines ?? this.tackleLines,
      tackleRigs: tackleRigs ?? this.tackleRigs,
      vesselNames: vesselNames ?? this.vesselNames,
      vesselPorts: vesselPorts ?? this.vesselPorts,
      vesselPoints: vesselPoints ?? this.vesselPoints,
      vesselFishTypes: vesselFishTypes ?? this.vesselFishTypes,
      locationFabRight: locationFabRight ?? this.locationFabRight,
      locationFabBottom: locationFabBottom ?? this.locationFabBottom,
      trackingFabRight: trackingFabRight ?? this.trackingFabRight,
      trackingFabBottom: trackingFabBottom ?? this.trackingFabBottom,
      commuteAlarmEnabled: commuteAlarmEnabled ?? this.commuteAlarmEnabled,
      commuteRadius: commuteRadius ?? this.commuteRadius,
      commuteSoundMode: commuteSoundMode ?? this.commuteSoundMode,
      commutePins: commutePins ?? this.commutePins,
      commuteAmStart: commuteAmStart ?? this.commuteAmStart,
      commuteAmEnd: commuteAmEnd ?? this.commuteAmEnd,
      commutePmStart: commutePmStart ?? this.commutePmStart,
      commutePmEnd: commutePmEnd ?? this.commutePmEnd,
      commuteCustomStart: commuteCustomStart ?? this.commuteCustomStart,
      commuteCustomEnd: commuteCustomEnd ?? this.commuteCustomEnd,
      commuteAmEnabled: commuteAmEnabled ?? this.commuteAmEnabled,
      commutePmEnabled: commutePmEnabled ?? this.commutePmEnabled,
      commuteCustomEnabled: commuteCustomEnabled ?? this.commuteCustomEnabled,
      commuteWeekdaysOnly: commuteWeekdaysOnly ?? this.commuteWeekdaysOnly,
      commuteAlarmActive: commuteAlarmActive ?? this.commuteAlarmActive,
    );
  }
}
