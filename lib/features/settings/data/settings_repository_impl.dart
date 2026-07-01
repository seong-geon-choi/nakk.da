import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_constants.dart';
import '../domain/models/app_settings.dart';
import '../domain/settings_repository.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  static const _saveUriKey = 'save_saf_uri';
  static const _saveDisplayPathKey = 'save_display_path';
  static const _photoSavePathKey = 'photo_save_path';
  static const _showLocationButtonKey = 'show_location_button';
  static const _autoLocationOnFirstEntryKey = 'auto_location_on_first_entry';
  static const _autoSaveVoiceKey = 'auto_save_voice';
  static const _showAddressInMemoNameKey = 'show_address_in_memo_name';
  static const _showCatchInputKey = 'show_catch_input'; // 구버전 마이그레이션용
  static const _memoComplexityKey = 'memo_complexity';
  static const _shareEnabledKey = 'share_enabled';
  static const _adsEnabledKey = 'ads_enabled';
  static const _khoaApiKeyKey = 'khoa_api_key';
  static const _watermarkKey = 'watermark_settings'; // 구버전 단일 워터마크(마이그레이션)
  static const _watermarkTemplatesKey = 'watermark_templates';
  static const _watermarkTemplateIndexKey = 'watermark_template_index';
  static const _showTrackingButtonKey = 'show_tracking_button';
  static const _locationTrackingEnabledKey = 'location_tracking_enabled';
  static const _trackingIntervalMetersKey = 'tracking_interval_meters';
  static const _quickLaunchModeKey = 'quick_launch_mode';
  static const _shakeThresholdGKey = 'shake_threshold_g';
  static const _driveBackupEnabledKey = 'drive_backup_enabled';
  static const _driveBackupIncludeMediaKey = 'drive_backup_include_media';
  static const _lastSyncAtKey = 'last_sync_at';
  static const _lastSyncSuccessKey = 'last_sync_success';
  static const _fishSpeciesKey = 'fish_species';
  static const _hiddenFishSpeciesKey = 'hidden_fish_species';
  static const _tackleRodsKey = 'tackle_rods';
  static const _tackleReelsKey = 'tackle_reels';
  static const _tackleLinesKey = 'tackle_lines';
  static const _tackleRigsKey = 'tackle_rigs';
  static const _vesselNamesKey = 'vessel_names';
  static const _vesselPortsKey = 'vessel_ports';
  static const _vesselPointsKey = 'vessel_points';
  static const _vesselFishTypesKey = 'vessel_fish_types';
  static const _locationFabRightKey = 'location_fab_right';
  static const _locationFabBottomKey = 'location_fab_bottom';
  static const _trackingFabRightKey = 'tracking_fab_right';
  static const _trackingFabBottomKey = 'tracking_fab_bottom';
  static const _commuteEnabledKey = 'commute_alarm_enabled';
  static const _commuteRadiusKey = 'commute_radius';
  static const _commuteSoundKey = 'commute_sound_mode';
  static const _commutePinsKey = 'commute_pins';
  static const _commuteAmStartKey = 'commute_am_start';
  static const _commuteAmEndKey = 'commute_am_end';
  static const _commutePmStartKey = 'commute_pm_start';
  static const _commutePmEndKey = 'commute_pm_end';
  static const _commuteWeekdaysOnlyKey = 'commute_weekdays_only';
  static const _commuteActiveKey = 'commute_alarm_active';
  static const _commuteCustomStartKey = 'commute_custom_start';
  static const _commuteCustomEndKey = 'commute_custom_end';
  static const _commuteAmEnabledKey = 'commute_am_enabled';
  static const _commutePmEnabledKey = 'commute_pm_enabled';
  static const _commuteCustomEnabledKey = 'commute_custom_enabled';

  static const defaultMemoDisplayPath = '/storage/emulated/0/Documents/nakkda';

  @override
  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saveUri = prefs.getString(_saveUriKey) ?? '';
    final saveDisplayPath = prefs.getString(_saveDisplayPathKey) ?? '';
    final storedPhotoPath = prefs.getString(_photoSavePathKey);
    final photoSavePath = (storedPhotoPath == null || storedPhotoPath.contains('/Pictures/'))
        ? await _defaultPhotoSavePath()
        : storedPhotoPath;
    final showLocationButton = prefs.getBool(_showLocationButtonKey) ?? true;
    final autoLocationOnFirstEntry =
        prefs.getBool(_autoLocationOnFirstEntryKey) ?? false;
    final autoSaveVoice = prefs.getBool(_autoSaveVoiceKey) ?? true;
    final showAddressInMemoName = prefs.getBool(_showAddressInMemoNameKey) ?? true;
    // 신규 키 우선. 없으면: 구버전 show_catch_input 있으면 이관(true→최소, false→일반),
    // 아무 것도 없으면(신규 설치) 기본값 낚시(상세).
    final memoComplexity = MemoComplexity.values.firstWhere(
      (e) => e.name == prefs.getString(_memoComplexityKey),
      orElse: () {
        final old = prefs.getBool(_showCatchInputKey);
        if (old == null) return MemoComplexity.complexFishing;
        return old ? MemoComplexity.simpleFishing : MemoComplexity.general;
      },
    );
    final shareEnabled = prefs.getBool(_shareEnabledKey) ?? true;
    final adsEnabled = prefs.getBool(_adsEnabledKey) ?? false;
    final khoaApiKey = prefs.getString(_khoaApiKeyKey);
    // 워터마크 템플릿 3슬롯. 신규 키 우선, 없으면 구버전 단일 워터마크에서 마이그레이션.
    List<WatermarkSettings> watermarkTemplates;
    final templatesJson = prefs.getString(_watermarkTemplatesKey);
    if (templatesJson != null) {
      final list = (jsonDecode(templatesJson) as List)
          .map((e) => WatermarkSettings.fromJson(e as Map<String, dynamic>))
          .toList();
      watermarkTemplates = [
        for (var i = 0; i < 3; i++)
          i < list.length ? list[i] : WatermarkSettings(),
      ];
    } else {
      final wmJson = prefs.getString(_watermarkKey);
      final legacy = wmJson != null
          ? WatermarkSettings.fromJson(jsonDecode(wmJson) as Map<String, dynamic>)
          : WatermarkSettings();
      watermarkTemplates = [legacy, WatermarkSettings(), WatermarkSettings()];
    }
    final watermarkTemplateIndex =
        (prefs.getInt(_watermarkTemplateIndexKey) ?? 0).clamp(0, 2);
    final showTrackingButton = prefs.getBool(_showTrackingButtonKey) ?? true;
    final locationTrackingEnabled = prefs.getBool(_locationTrackingEnabledKey) ?? false;
    final trackingIntervalMeters = prefs.getInt(_trackingIntervalMetersKey) ?? 100;
    final quickLaunchModeStr = prefs.getString(_quickLaunchModeKey) ?? 'shake';
    final quickLaunchMode = QuickLaunchMode.values.firstWhere(
      (e) => e.name == quickLaunchModeStr,
      orElse: () => QuickLaunchMode.shake,
    );
    final shakeThresholdG = prefs.getDouble(_shakeThresholdGKey) ?? 3.5;
    final driveBackupEnabled = prefs.getBool(_driveBackupEnabledKey) ?? false;
    final driveBackupIncludeMedia = prefs.getBool(_driveBackupIncludeMediaKey) ?? false;
    final lastSyncAtMs = prefs.getInt(_lastSyncAtKey);
    final lastSyncAt = lastSyncAtMs != null
        ? DateTime.fromMillisecondsSinceEpoch(lastSyncAtMs)
        : null;
    final lastSyncSuccessRaw = prefs.getBool(_lastSyncSuccessKey);
    // 저장된 어종 목록이 있으면, 새로 추가된 기본 어종(누락분)을 뒤에 병합한다.
    // (사용자가 추가한 어종·순서는 유지. null이면 AppSettings가 전체 기본값 사용)
    final savedFishSpecies = prefs.getStringList(_fishSpeciesKey);
    final fishSpecies = savedFishSpecies == null
        ? null
        : [
            ...savedFishSpecies,
            ...kCommonFishSpecies.where((s) => !savedFishSpecies.contains(s)),
          ];
    final hiddenFishSpecies = prefs.getStringList(_hiddenFishSpeciesKey) ?? const [];
    final tackleRods = prefs.getStringList(_tackleRodsKey) ?? const [];
    final tackleReels = prefs.getStringList(_tackleReelsKey) ?? const [];
    final tackleLines = prefs.getStringList(_tackleLinesKey) ?? const [];
    final tackleRigs = prefs.getStringList(_tackleRigsKey) ?? const [];
    final vesselNames = prefs.getStringList(_vesselNamesKey) ?? const [];
    final vesselPorts = prefs.getStringList(_vesselPortsKey) ?? const [];
    final vesselPoints = prefs.getStringList(_vesselPointsKey) ?? const [];
    final vesselFishTypes = prefs.getStringList(_vesselFishTypesKey) ?? const [];
    final locationFabRight = prefs.getDouble(_locationFabRightKey) ?? 16;
    final locationFabBottom = prefs.getDouble(_locationFabBottomKey) ?? 100;
    final trackingFabRight = prefs.getDouble(_trackingFabRightKey) ?? 16;
    final trackingFabBottom = prefs.getDouble(_trackingFabBottomKey) ?? 172;
    final commuteAlarmEnabled = prefs.getBool(_commuteEnabledKey) ?? false;
    final commuteRadius = prefs.getInt(_commuteRadiusKey) ?? 700;
    final commuteSoundStr = prefs.getString(_commuteSoundKey);
    final commuteSoundMode = CommuteSoundMode.values.firstWhere(
      (e) => e.name == commuteSoundStr,
      orElse: () => CommuteSoundMode.systemDefault,
    );
    final commutePinsStr = prefs.getString(_commutePinsKey);
    final commutePins = commutePinsStr != null
        ? (jsonDecode(commutePinsStr) as List<dynamic>)
            .map((e) => CommutePin.fromJson(e as Map<String, dynamic>))
            .toList()
        : const <CommutePin>[];
    final commuteAmStart = prefs.getInt(_commuteAmStartKey) ?? 480;
    final commuteAmEnd = prefs.getInt(_commuteAmEndKey) ?? 540;
    final commutePmStart = prefs.getInt(_commutePmStartKey) ?? 1140;
    final commutePmEnd = prefs.getInt(_commutePmEndKey) ?? 1200;
    final commuteWeekdaysOnly = prefs.getBool(_commuteWeekdaysOnlyKey) ?? true;
    final commuteAlarmActive = prefs.getBool(_commuteActiveKey) ?? true;
    final commuteCustomStart = prefs.getInt(_commuteCustomStartKey) ?? 600;
    final commuteCustomEnd = prefs.getInt(_commuteCustomEndKey) ?? 720;
    final commuteAmEnabled = prefs.getBool(_commuteAmEnabledKey) ?? true;
    final commutePmEnabled = prefs.getBool(_commutePmEnabledKey) ?? true;
    final commuteCustomEnabled = prefs.getBool(_commuteCustomEnabledKey) ?? false;

    return AppSettings(
      savePath: saveUri,
      saveDisplayPath: saveDisplayPath,
      photoSavePath: photoSavePath,
      showLocationButton: showLocationButton,
      autoLocationOnFirstEntry: autoLocationOnFirstEntry,
      autoSaveVoice: autoSaveVoice,
      showAddressInMemoName: showAddressInMemoName,
      memoComplexity: memoComplexity,
      shareEnabled: shareEnabled,
      adsEnabled: adsEnabled,
      khoaApiKey: khoaApiKey,
      watermarkTemplates: watermarkTemplates,
      watermarkTemplateIndex: watermarkTemplateIndex,
      showTrackingButton: showTrackingButton,
      locationTrackingEnabled: locationTrackingEnabled,
      trackingIntervalMeters: trackingIntervalMeters,
      quickLaunchMode: quickLaunchMode,
      shakeThresholdG: shakeThresholdG,
      driveBackupEnabled: driveBackupEnabled,
      driveBackupIncludeMedia: driveBackupIncludeMedia,
      lastSyncAt: lastSyncAt,
      lastSyncSuccess: lastSyncSuccessRaw,
      fishSpecies: fishSpecies, // null이면 AppSettings 기본값(kCommonFishSpecies)
      hiddenFishSpecies: hiddenFishSpecies,
      tackleRods: tackleRods,
      tackleReels: tackleReels,
      tackleLines: tackleLines,
      tackleRigs: tackleRigs,
      vesselNames: vesselNames,
      vesselPorts: vesselPorts,
      vesselPoints: vesselPoints,
      vesselFishTypes: vesselFishTypes,
      locationFabRight: locationFabRight,
      locationFabBottom: locationFabBottom,
      trackingFabRight: trackingFabRight,
      trackingFabBottom: trackingFabBottom,
      commuteAlarmEnabled: commuteAlarmEnabled,
      commuteRadius: commuteRadius,
      commuteSoundMode: commuteSoundMode,
      commutePins: commutePins,
      commuteAmStart: commuteAmStart,
      commuteAmEnd: commuteAmEnd,
      commutePmStart: commutePmStart,
      commutePmEnd: commutePmEnd,
      commuteWeekdaysOnly: commuteWeekdaysOnly,
      commuteAlarmActive: commuteAlarmActive,
      commuteCustomStart: commuteCustomStart,
      commuteCustomEnd: commuteCustomEnd,
      commuteAmEnabled: commuteAmEnabled,
      commutePmEnabled: commutePmEnabled,
      commuteCustomEnabled: commuteCustomEnabled,
    );
  }

  @override
  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_saveUriKey, settings.savePath);
    await prefs.setString(_saveDisplayPathKey, settings.saveDisplayPath);
    await prefs.setString(_photoSavePathKey, settings.photoSavePath);
    await prefs.setBool(_showLocationButtonKey, settings.showLocationButton);
    await prefs.setBool(
        _autoLocationOnFirstEntryKey, settings.autoLocationOnFirstEntry);
    await prefs.setBool(_autoSaveVoiceKey, settings.autoSaveVoice);
    await prefs.setBool(_showAddressInMemoNameKey, settings.showAddressInMemoName);
    await prefs.setString(_memoComplexityKey, settings.memoComplexity.name);
    await prefs.setBool(_shareEnabledKey, settings.shareEnabled);
    await prefs.setBool(_adsEnabledKey, settings.adsEnabled);
    if (settings.khoaApiKey != null) {
      await prefs.setString(_khoaApiKeyKey, settings.khoaApiKey!);
    } else {
      await prefs.remove(_khoaApiKeyKey);
    }
    await prefs.setString(_watermarkTemplatesKey,
        jsonEncode(settings.watermarkTemplates.map((t) => t.toJson()).toList()));
    await prefs.setInt(
        _watermarkTemplateIndexKey, settings.watermarkTemplateIndex);
    await prefs.setBool(_showTrackingButtonKey, settings.showTrackingButton);
    await prefs.setBool(_locationTrackingEnabledKey, settings.locationTrackingEnabled);
    await prefs.setInt(_trackingIntervalMetersKey, settings.trackingIntervalMeters);
    await prefs.setString(_quickLaunchModeKey, settings.quickLaunchMode.name);
    await prefs.setDouble(_shakeThresholdGKey, settings.shakeThresholdG);
    await prefs.setBool(_driveBackupEnabledKey, settings.driveBackupEnabled);
    await prefs.setBool(_driveBackupIncludeMediaKey, settings.driveBackupIncludeMedia);
    if (settings.lastSyncAt != null) {
      await prefs.setInt(_lastSyncAtKey, settings.lastSyncAt!.millisecondsSinceEpoch);
    } else {
      await prefs.remove(_lastSyncAtKey);
    }
    if (settings.lastSyncSuccess != null) {
      await prefs.setBool(_lastSyncSuccessKey, settings.lastSyncSuccess!);
    } else {
      await prefs.remove(_lastSyncSuccessKey);
    }
    await prefs.setStringList(_fishSpeciesKey, settings.fishSpecies);
    await prefs.setStringList(_hiddenFishSpeciesKey, settings.hiddenFishSpecies);
    await prefs.setStringList(_tackleRodsKey, settings.tackleRods);
    await prefs.setStringList(_tackleReelsKey, settings.tackleReels);
    await prefs.setStringList(_tackleLinesKey, settings.tackleLines);
    await prefs.setStringList(_tackleRigsKey, settings.tackleRigs);
    await prefs.setStringList(_vesselNamesKey, settings.vesselNames);
    await prefs.setStringList(_vesselPortsKey, settings.vesselPorts);
    await prefs.setStringList(_vesselPointsKey, settings.vesselPoints);
    await prefs.setStringList(_vesselFishTypesKey, settings.vesselFishTypes);
    await prefs.setDouble(_locationFabRightKey, settings.locationFabRight);
    await prefs.setDouble(_locationFabBottomKey, settings.locationFabBottom);
    await prefs.setDouble(_trackingFabRightKey, settings.trackingFabRight);
    await prefs.setDouble(_trackingFabBottomKey, settings.trackingFabBottom);
    await prefs.setBool(_commuteEnabledKey, settings.commuteAlarmEnabled);
    await prefs.setInt(_commuteRadiusKey, settings.commuteRadius);
    await prefs.setString(_commuteSoundKey, settings.commuteSoundMode.name);
    await prefs.setString(_commutePinsKey,
        jsonEncode(settings.commutePins.map((p) => p.toJson()).toList()));
    await prefs.setInt(_commuteAmStartKey, settings.commuteAmStart);
    await prefs.setInt(_commuteAmEndKey, settings.commuteAmEnd);
    await prefs.setInt(_commutePmStartKey, settings.commutePmStart);
    await prefs.setInt(_commutePmEndKey, settings.commutePmEnd);
    await prefs.setBool(_commuteWeekdaysOnlyKey, settings.commuteWeekdaysOnly);
    await prefs.setBool(_commuteActiveKey, settings.commuteAlarmActive);
    await prefs.setInt(_commuteCustomStartKey, settings.commuteCustomStart);
    await prefs.setInt(_commuteCustomEndKey, settings.commuteCustomEnd);
    await prefs.setBool(_commuteAmEnabledKey, settings.commuteAmEnabled);
    await prefs.setBool(_commutePmEnabledKey, settings.commutePmEnabled);
    await prefs.setBool(_commuteCustomEnabledKey, settings.commuteCustomEnabled);
  }

  Future<String> _defaultPhotoSavePath() async {
    final appDir = await getExternalStorageDirectory();
    if (appDir != null) {
      final base = appDir.path.split('/Android/').first;
      return '$base/DCIM/nakkda';
    }
    return '${(await getApplicationDocumentsDirectory()).path}/DCIM/nakkda';
  }
}
