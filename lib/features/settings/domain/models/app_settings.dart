import '../../../../core/constants/api_keys.dart';
import '../../../../core/constants/app_constants.dart';

// ── 워터마크 열거형 ────────────────────────────────────────────

enum WatermarkPosition { topLeft, topRight, bottomLeft, bottomRight }
enum WatermarkLineType { date, time, customText }
enum WatermarkAlign { left, center, right }
enum WatermarkFont { sansSerif, monospace, serif }

// ── 워터마크 라인 ─────────────────────────────────────────────

class WatermarkLine {
  final WatermarkLineType type;
  final bool visible;
  final String customText;

  const WatermarkLine({
    required this.type,
    this.visible = true,
    this.customText = '',
  });

  WatermarkLine copyWith({bool? visible, String? customText}) => WatermarkLine(
        type: type,
        visible: visible ?? this.visible,
        customText: customText ?? this.customText,
      );

  Map<String, dynamic> toJson() =>
      {'type': type.name, 'visible': visible, 'customText': customText};

  factory WatermarkLine.fromJson(Map<String, dynamic> j) => WatermarkLine(
        type: WatermarkLineType.values.byName(j['type'] as String? ?? 'date'),
        visible: j['visible'] as bool? ?? true,
        customText: j['customText'] as String? ?? '',
      );
}

// ── 워터마크 전체 설정 ─────────────────────────────────────────

class WatermarkSettings {
  final bool enabled;
  final List<WatermarkLine> lines;
  final WatermarkPosition position;
  final double fontSize;
  final bool bold;
  final WatermarkAlign alignment;
  final WatermarkFont fontFamily;
  final String dateFormat;
  final String timeFormat;
  final double boxOpacity; // 0.1 ~ 1.0
  final double posX; // 0(좌)~1(우) 자유 위치
  final double posY; // 0(상)~1(하) 자유 위치

  static const List<WatermarkLine> defaultLines = [
    WatermarkLine(type: WatermarkLineType.date),
    WatermarkLine(type: WatermarkLineType.time),
    WatermarkLine(type: WatermarkLineType.customText, visible: false),
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
    List<WatermarkLine>? lines,
    this.position = WatermarkPosition.bottomRight,
    this.fontSize = 32,
    this.bold = false,
    this.alignment = WatermarkAlign.right,
    this.fontFamily = WatermarkFont.sansSerif,
    this.dateFormat = 'yyyy-MM-dd',
    this.timeFormat = 'HH:mm',
    this.boxOpacity = 0.67,
    this.posX = 1.0,
    this.posY = 1.0,
  }) : lines = lines ?? defaultLines;

  WatermarkSettings copyWith({
    bool? enabled,
    List<WatermarkLine>? lines,
    WatermarkPosition? position,
    double? fontSize,
    bool? bold,
    WatermarkAlign? alignment,
    WatermarkFont? fontFamily,
    String? dateFormat,
    String? timeFormat,
    double? boxOpacity,
    double? posX,
    double? posY,
  }) =>
      WatermarkSettings(
        enabled: enabled ?? this.enabled,
        lines: lines ?? this.lines,
        position: position ?? this.position,
        fontSize: fontSize ?? this.fontSize,
        bold: bold ?? this.bold,
        alignment: alignment ?? this.alignment,
        fontFamily: fontFamily ?? this.fontFamily,
        dateFormat: dateFormat ?? this.dateFormat,
        timeFormat: timeFormat ?? this.timeFormat,
        boxOpacity: boxOpacity ?? this.boxOpacity,
        posX: posX ?? this.posX,
        posY: posY ?? this.posY,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'lines': lines.map((l) => l.toJson()).toList(),
        'position': position.name,
        'fontSize': fontSize,
        'bold': bold,
        'alignment': alignment.name,
        'fontFamily': fontFamily.name,
        'dateFormat': dateFormat,
        'timeFormat': timeFormat,
        'boxOpacity': boxOpacity,
        'posX': posX,
        'posY': posY,
      };

  factory WatermarkSettings.fromJson(Map<String, dynamic> j) {
    final position = WatermarkPosition.values
        .byName(j['position'] as String? ?? 'bottomRight');
    // 구 설정엔 posX/posY가 없으므로 코너 enum에서 유도
    final fallback = posFromCorner(position);
    final rawLines = j['lines'] as List<dynamic>?;
    return WatermarkSettings(
      enabled: j['enabled'] as bool? ?? false,
      lines: rawLines
          ?.map((l) => WatermarkLine.fromJson(l as Map<String, dynamic>))
          .toList(),
      position: position,
      fontSize: (j['fontSize'] as num?)?.toDouble() ?? 32,
      bold: j['bold'] as bool? ?? false,
      alignment:
          WatermarkAlign.values.byName(j['alignment'] as String? ?? 'right'),
      fontFamily: WatermarkFont.values
          .byName(j['fontFamily'] as String? ?? 'sansSerif'),
      dateFormat: j['dateFormat'] as String? ?? 'yyyy-MM-dd',
      timeFormat: j['timeFormat'] as String? ?? 'HH:mm',
      boxOpacity: (j['boxOpacity'] as num?)?.toDouble() ?? 0.67,
      posX: (j['posX'] as num?)?.toDouble() ?? fallback.$1,
      posY: (j['posY'] as num?)?.toDouble() ?? fallback.$2,
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
