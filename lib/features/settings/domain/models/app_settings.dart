import '../../../../core/constants/api_keys.dart';

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

  static const List<WatermarkLine> defaultLines = [
    WatermarkLine(type: WatermarkLineType.date),
    WatermarkLine(type: WatermarkLineType.time),
    WatermarkLine(type: WatermarkLineType.customText, visible: false),
  ];

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
      };

  factory WatermarkSettings.fromJson(Map<String, dynamic> j) {
    final rawLines = j['lines'] as List<dynamic>?;
    return WatermarkSettings(
      enabled: j['enabled'] as bool? ?? false,
      lines: rawLines
          ?.map((l) => WatermarkLine.fromJson(l as Map<String, dynamic>))
          .toList(),
      position: WatermarkPosition.values
          .byName(j['position'] as String? ?? 'bottomRight'),
      fontSize: (j['fontSize'] as num?)?.toDouble() ?? 32,
      bold: j['bold'] as bool? ?? false,
      alignment:
          WatermarkAlign.values.byName(j['alignment'] as String? ?? 'right'),
      fontFamily: WatermarkFont.values
          .byName(j['fontFamily'] as String? ?? 'sansSerif'),
      dateFormat: j['dateFormat'] as String? ?? 'yyyy-MM-dd',
      timeFormat: j['timeFormat'] as String? ?? 'HH:mm',
      boxOpacity: (j['boxOpacity'] as num?)?.toDouble() ?? 0.67,
    );
  }
}

// ── 앱 전체 설정 ───────────────────────────────────────────────

class AppSettings {
  final String savePath;
  final String photoSavePath;
  final bool showLocationButton;
  final bool autoSaveVoice;
  final String? khoaApiKey;
  final WatermarkSettings watermark;

  AppSettings({
    required this.savePath,
    required this.photoSavePath,
    this.showLocationButton = true,
    this.autoSaveVoice = false,
    this.khoaApiKey,
    WatermarkSettings? watermark,
  }) : watermark = watermark ?? WatermarkSettings();

  String get effectiveKhoaApiKey {
    final key = khoaApiKey?.trim();
    return (key != null && key.isNotEmpty) ? key : kDefaultKhoaApiKey;
  }

  AppSettings copyWith({
    String? savePath,
    String? photoSavePath,
    bool? showLocationButton,
    bool? autoSaveVoice,
    String? khoaApiKey,
    bool clearKhoaApiKey = false,
    WatermarkSettings? watermark,
  }) {
    return AppSettings(
      savePath: savePath ?? this.savePath,
      photoSavePath: photoSavePath ?? this.photoSavePath,
      showLocationButton: showLocationButton ?? this.showLocationButton,
      autoSaveVoice: autoSaveVoice ?? this.autoSaveVoice,
      khoaApiKey: clearKhoaApiKey ? null : (khoaApiKey ?? this.khoaApiKey),
      watermark: watermark ?? this.watermark,
    );
  }
}
