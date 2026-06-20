import '../../../../core/constants/api_keys.dart';
import '../../../../core/constants/app_constants.dart';

// ── 워터마크 열거형 ────────────────────────────────────────────

enum WatermarkPosition { topLeft, topRight, bottomLeft, bottomRight }
enum WatermarkLineType { date, time, customText }
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

  /// 컨테이너 배경 프리셋 색상 (불투명 ARGB 기준)
  static const List<int> bgPresets = [
    0xFF000000, // 검정
    0xFF424242, // 진회색
    0xFFFFFFFF, // 흰색
    0xFF0D47A1, // 남색
    0xFF1B5E20, // 초록
    0xFFB71C1C, // 빨강
  ];

  /// 글자색 프리셋 (박스별 선택)
  static const List<int> textPresets = [
    0xFFFFFFFF, // 흰색
    0xFF000000, // 검정
    0xFF9E9E9E, // 회색
    0xFFF44336, // 빨강
    0xFFE91E63, // 핑크
    0xFFFF9800, // 주황
    0xFFFFEB3B, // 노랑
    0xFFCDDC39, // 라임
    0xFF4CAF50, // 초록
    0xFF009688, // 청록
    0xFF00BCD4, // 시안
    0xFF2196F3, // 파랑
    0xFF3F51B5, // 남색
    0xFF9C27B0, // 보라
    0xFF795548, // 갈색
    0xFFFF4081, // 형광핑크
  ];

  /// 기본 박스 3종 (세로 스택)
  static List<WatermarkBox> defaultBoxes() => const [
        WatermarkBox(type: WatermarkLineType.date, dy: 0.0),
        WatermarkBox(type: WatermarkLineType.time, dy: 0.12),
        WatermarkBox(
            type: WatermarkLineType.customText, visible: false, dy: 0.24),
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
    this.containerPosX = 1.0,
    this.containerPosY = 1.0,
    this.bgColorIndex = 0,
    this.bgOpacity = 0.67,
    this.hideContainerBorder = false,
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
  }) =>
      WatermarkSettings(
        enabled: enabled ?? this.enabled,
        boxes: boxes ?? this.boxes,
        containerPosX: containerPosX ?? this.containerPosX,
        containerPosY: containerPosY ?? this.containerPosY,
        bgColorIndex: bgColorIndex ?? this.bgColorIndex,
        bgOpacity: bgOpacity ?? this.bgOpacity,
        hideContainerBorder: hideContainerBorder ?? this.hideContainerBorder,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'boxes': boxes.map((b) => b.toJson()).toList(),
        'containerPosX': containerPosX,
        'containerPosY': containerPosY,
        'bgColorIndex': bgColorIndex,
        'bgOpacity': bgOpacity,
        'hideContainerBorder': hideContainerBorder,
      };

  factory WatermarkSettings.fromJson(Map<String, dynamic> j) {
    // 신 포맷
    if (j['boxes'] != null) {
      return WatermarkSettings(
        enabled: j['enabled'] as bool? ?? false,
        boxes: (j['boxes'] as List<dynamic>)
            .map((b) => WatermarkBox.fromJson(b as Map<String, dynamic>))
            .toList(),
        containerPosX: (j['containerPosX'] as num?)?.toDouble() ?? 1.0,
        containerPosY: (j['containerPosY'] as num?)?.toDouble() ?? 1.0,
        bgColorIndex: (j['bgColorIndex'] as num?)?.toInt() ?? 0,
        bgOpacity: (j['bgOpacity'] as num?)?.toDouble() ?? 0.67,
        hideContainerBorder: j['hideContainerBorder'] as bool? ?? false,
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

class AppSettings {
  final String savePath;       // SAF URI (content://) 또는 빈 문자열
  final String saveDisplayPath; // 사람이 읽을 수 있는 경로 (UI 표시용)
  final String photoSavePath;
  final bool showLocationButton;
  final bool autoSaveVoice;
  final bool showAddressInMemoName;
  final bool showCatchInput; // 메모 작성 시 어종·길이 입력 항목 표시 여부
  final bool shareEnabled; // 메모 공유 버튼 표시 여부 (향후 유료화 대비 토글)
  final bool adsEnabled; // 광고 노출 여부 (개발자 메뉴 토글, 기본 off)
  final String? khoaApiKey;
  final WatermarkSettings watermark;
  final bool showTrackingButton;
  final bool locationTrackingEnabled;
  final int trackingIntervalMeters;
  final QuickLaunchMode quickLaunchMode;
  final bool driveBackupEnabled;
  final bool driveBackupIncludeMedia;
  final DateTime? lastSyncAt;
  final bool? lastSyncSuccess;
  final List<String> fishSpecies; // 어종 입력 목록 (사용자 편집 가능)
  final List<String> hiddenFishSpecies; // 메모 드롭다운에서 숨길(체크 해제) 어종
  final double locationFabRight;  // 홈 '환경 추가' FAB 위치 (right)
  final double locationFabBottom; // 홈 '환경 추가' FAB 위치 (bottom)
  final double trackingFabRight;  // 홈 트래킹 FAB 위치 (right)
  final double trackingFabBottom; // 홈 트래킹 FAB 위치 (bottom)

  bool get needsFolderSetup => savePath.isEmpty;

  /// 메모 작성 드롭다운에 노출할 어종 (숨김 제외).
  /// 주의: 음성/메모 텍스트 어종 탐지는 항상 전체 [fishSpecies]를 사용한다.
  List<String> get visibleFishSpecies =>
      fishSpecies.where((s) => !hiddenFishSpecies.contains(s)).toList();

  AppSettings({
    required this.savePath,
    this.saveDisplayPath = '',
    required this.photoSavePath,
    this.showLocationButton = true,
    this.autoSaveVoice = true,
    this.showAddressInMemoName = true,
    this.showCatchInput = true,
    this.shareEnabled = true,
    this.adsEnabled = false,
    this.khoaApiKey,
    WatermarkSettings? watermark,
    this.showTrackingButton = true,
    this.locationTrackingEnabled = false,
    this.trackingIntervalMeters = 100,
    this.quickLaunchMode = QuickLaunchMode.shake,
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
    bool? autoSaveVoice,
    bool? showAddressInMemoName,
    bool? showCatchInput,
    bool? shareEnabled,
    bool? adsEnabled,
    String? khoaApiKey,
    bool clearKhoaApiKey = false,
    WatermarkSettings? watermark,
    bool? showTrackingButton,
    bool? locationTrackingEnabled,
    int? trackingIntervalMeters,
    QuickLaunchMode? quickLaunchMode,
    bool? driveBackupEnabled,
    bool? driveBackupIncludeMedia,
    DateTime? lastSyncAt,
    bool? lastSyncSuccess,
    bool clearLastSync = false,
    List<String>? fishSpecies,
    List<String>? hiddenFishSpecies,
    double? locationFabRight,
    double? locationFabBottom,
    double? trackingFabRight,
    double? trackingFabBottom,
  }) {
    return AppSettings(
      savePath: savePath ?? this.savePath,
      saveDisplayPath: saveDisplayPath ?? this.saveDisplayPath,
      photoSavePath: photoSavePath ?? this.photoSavePath,
      showLocationButton: showLocationButton ?? this.showLocationButton,
      autoSaveVoice: autoSaveVoice ?? this.autoSaveVoice,
      showAddressInMemoName: showAddressInMemoName ?? this.showAddressInMemoName,
      showCatchInput: showCatchInput ?? this.showCatchInput,
      shareEnabled: shareEnabled ?? this.shareEnabled,
      adsEnabled: adsEnabled ?? this.adsEnabled,
      khoaApiKey: clearKhoaApiKey ? null : (khoaApiKey ?? this.khoaApiKey),
      watermark: watermark ?? this.watermark,
      showTrackingButton: showTrackingButton ?? this.showTrackingButton,
      locationTrackingEnabled: locationTrackingEnabled ?? this.locationTrackingEnabled,
      trackingIntervalMeters: trackingIntervalMeters ?? this.trackingIntervalMeters,
      quickLaunchMode: quickLaunchMode ?? this.quickLaunchMode,
      driveBackupEnabled: driveBackupEnabled ?? this.driveBackupEnabled,
      driveBackupIncludeMedia: driveBackupIncludeMedia ?? this.driveBackupIncludeMedia,
      lastSyncAt: clearLastSync ? null : (lastSyncAt ?? this.lastSyncAt),
      lastSyncSuccess: clearLastSync ? null : (lastSyncSuccess ?? this.lastSyncSuccess),
      fishSpecies: fishSpecies ?? this.fishSpecies,
      hiddenFishSpecies: hiddenFishSpecies ?? this.hiddenFishSpecies,
      locationFabRight: locationFabRight ?? this.locationFabRight,
      locationFabBottom: locationFabBottom ?? this.locationFabBottom,
      trackingFabRight: trackingFabRight ?? this.trackingFabRight,
      trackingFabBottom: trackingFabBottom ?? this.trackingFabBottom,
    );
  }
}
