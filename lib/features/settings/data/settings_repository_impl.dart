import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models/app_settings.dart';
import '../domain/settings_repository.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  static const _saveUriKey = 'save_saf_uri';
  static const _saveDisplayPathKey = 'save_display_path';
  static const _photoSavePathKey = 'photo_save_path';
  static const _showLocationButtonKey = 'show_location_button';
  static const _autoSaveVoiceKey = 'auto_save_voice';
  static const _showAddressInMemoNameKey = 'show_address_in_memo_name';
  static const _showCatchInputKey = 'show_catch_input';
  static const _shareEnabledKey = 'share_enabled';
  static const _khoaApiKeyKey = 'khoa_api_key';
  static const _watermarkKey = 'watermark_settings';
  static const _showTrackingButtonKey = 'show_tracking_button';
  static const _locationTrackingEnabledKey = 'location_tracking_enabled';
  static const _trackingIntervalMetersKey = 'tracking_interval_meters';
  static const _quickLaunchModeKey = 'quick_launch_mode';
  static const _driveBackupEnabledKey = 'drive_backup_enabled';
  static const _driveBackupIncludeMediaKey = 'drive_backup_include_media';
  static const _lastSyncAtKey = 'last_sync_at';
  static const _lastSyncSuccessKey = 'last_sync_success';
  static const _fishSpeciesKey = 'fish_species';
  static const _hiddenFishSpeciesKey = 'hidden_fish_species';
  static const _locationFabRightKey = 'location_fab_right';
  static const _locationFabBottomKey = 'location_fab_bottom';
  static const _trackingFabRightKey = 'tracking_fab_right';
  static const _trackingFabBottomKey = 'tracking_fab_bottom';

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
    final autoSaveVoice = prefs.getBool(_autoSaveVoiceKey) ?? true;
    final showAddressInMemoName = prefs.getBool(_showAddressInMemoNameKey) ?? true;
    final showCatchInput = prefs.getBool(_showCatchInputKey) ?? true;
    final shareEnabled = prefs.getBool(_shareEnabledKey) ?? false;
    final khoaApiKey = prefs.getString(_khoaApiKeyKey);
    final wmJson = prefs.getString(_watermarkKey);
    final watermark = wmJson != null
        ? WatermarkSettings.fromJson(jsonDecode(wmJson) as Map<String, dynamic>)
        : WatermarkSettings();
    final showTrackingButton = prefs.getBool(_showTrackingButtonKey) ?? true;
    final locationTrackingEnabled = prefs.getBool(_locationTrackingEnabledKey) ?? false;
    final trackingIntervalMeters = prefs.getInt(_trackingIntervalMetersKey) ?? 100;
    final quickLaunchModeStr = prefs.getString(_quickLaunchModeKey) ?? 'shake';
    final quickLaunchMode = QuickLaunchMode.values.firstWhere(
      (e) => e.name == quickLaunchModeStr,
      orElse: () => QuickLaunchMode.shake,
    );
    final driveBackupEnabled = prefs.getBool(_driveBackupEnabledKey) ?? false;
    final driveBackupIncludeMedia = prefs.getBool(_driveBackupIncludeMediaKey) ?? false;
    final lastSyncAtMs = prefs.getInt(_lastSyncAtKey);
    final lastSyncAt = lastSyncAtMs != null
        ? DateTime.fromMillisecondsSinceEpoch(lastSyncAtMs)
        : null;
    final lastSyncSuccessRaw = prefs.getBool(_lastSyncSuccessKey);
    final fishSpecies = prefs.getStringList(_fishSpeciesKey);
    final hiddenFishSpecies = prefs.getStringList(_hiddenFishSpeciesKey) ?? const [];
    final locationFabRight = prefs.getDouble(_locationFabRightKey) ?? 16;
    final locationFabBottom = prefs.getDouble(_locationFabBottomKey) ?? 100;
    final trackingFabRight = prefs.getDouble(_trackingFabRightKey) ?? 16;
    final trackingFabBottom = prefs.getDouble(_trackingFabBottomKey) ?? 172;

    return AppSettings(
      savePath: saveUri,
      saveDisplayPath: saveDisplayPath,
      photoSavePath: photoSavePath,
      showLocationButton: showLocationButton,
      autoSaveVoice: autoSaveVoice,
      showAddressInMemoName: showAddressInMemoName,
      showCatchInput: showCatchInput,
      shareEnabled: shareEnabled,
      khoaApiKey: khoaApiKey,
      watermark: watermark,
      showTrackingButton: showTrackingButton,
      locationTrackingEnabled: locationTrackingEnabled,
      trackingIntervalMeters: trackingIntervalMeters,
      quickLaunchMode: quickLaunchMode,
      driveBackupEnabled: driveBackupEnabled,
      driveBackupIncludeMedia: driveBackupIncludeMedia,
      lastSyncAt: lastSyncAt,
      lastSyncSuccess: lastSyncSuccessRaw,
      fishSpecies: fishSpecies, // null이면 AppSettings 기본값(kCommonFishSpecies)
      hiddenFishSpecies: hiddenFishSpecies,
      locationFabRight: locationFabRight,
      locationFabBottom: locationFabBottom,
      trackingFabRight: trackingFabRight,
      trackingFabBottom: trackingFabBottom,
    );
  }

  @override
  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_saveUriKey, settings.savePath);
    await prefs.setString(_saveDisplayPathKey, settings.saveDisplayPath);
    await prefs.setString(_photoSavePathKey, settings.photoSavePath);
    await prefs.setBool(_showLocationButtonKey, settings.showLocationButton);
    await prefs.setBool(_autoSaveVoiceKey, settings.autoSaveVoice);
    await prefs.setBool(_showAddressInMemoNameKey, settings.showAddressInMemoName);
    await prefs.setBool(_showCatchInputKey, settings.showCatchInput);
    await prefs.setBool(_shareEnabledKey, settings.shareEnabled);
    if (settings.khoaApiKey != null) {
      await prefs.setString(_khoaApiKeyKey, settings.khoaApiKey!);
    } else {
      await prefs.remove(_khoaApiKeyKey);
    }
    await prefs.setString(_watermarkKey, jsonEncode(settings.watermark.toJson()));
    await prefs.setBool(_showTrackingButtonKey, settings.showTrackingButton);
    await prefs.setBool(_locationTrackingEnabledKey, settings.locationTrackingEnabled);
    await prefs.setInt(_trackingIntervalMetersKey, settings.trackingIntervalMeters);
    await prefs.setString(_quickLaunchModeKey, settings.quickLaunchMode.name);
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
    await prefs.setDouble(_locationFabRightKey, settings.locationFabRight);
    await prefs.setDouble(_locationFabBottomKey, settings.locationFabBottom);
    await prefs.setDouble(_trackingFabRightKey, settings.trackingFabRight);
    await prefs.setDouble(_trackingFabBottomKey, settings.trackingFabBottom);
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
