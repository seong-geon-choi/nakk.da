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
  static const _khoaApiKeyKey = 'khoa_api_key';
  static const _watermarkKey = 'watermark_settings';
  static const _showTrackingButtonKey = 'show_tracking_button';
  static const _locationTrackingEnabledKey = 'location_tracking_enabled';
  static const _trackingIntervalMetersKey = 'tracking_interval_meters';

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
    final autoSaveVoice = prefs.getBool(_autoSaveVoiceKey) ?? false;
    final showAddressInMemoName = prefs.getBool(_showAddressInMemoNameKey) ?? true;
    final khoaApiKey = prefs.getString(_khoaApiKeyKey);
    final wmJson = prefs.getString(_watermarkKey);
    final watermark = wmJson != null
        ? WatermarkSettings.fromJson(jsonDecode(wmJson) as Map<String, dynamic>)
        : WatermarkSettings();
    final showTrackingButton = prefs.getBool(_showTrackingButtonKey) ?? true;
    final locationTrackingEnabled = prefs.getBool(_locationTrackingEnabledKey) ?? false;
    final trackingIntervalMeters = prefs.getInt(_trackingIntervalMetersKey) ?? 100;
    return AppSettings(
      savePath: saveUri,
      saveDisplayPath: saveDisplayPath,
      photoSavePath: photoSavePath,
      showLocationButton: showLocationButton,
      autoSaveVoice: autoSaveVoice,
      showAddressInMemoName: showAddressInMemoName,
      khoaApiKey: khoaApiKey,
      watermark: watermark,
      showTrackingButton: showTrackingButton,
      locationTrackingEnabled: locationTrackingEnabled,
      trackingIntervalMeters: trackingIntervalMeters,
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
    if (settings.khoaApiKey != null) {
      await prefs.setString(_khoaApiKeyKey, settings.khoaApiKey!);
    } else {
      await prefs.remove(_khoaApiKeyKey);
    }
    await prefs.setString(_watermarkKey, jsonEncode(settings.watermark.toJson()));
    await prefs.setBool(_showTrackingButtonKey, settings.showTrackingButton);
    await prefs.setBool(_locationTrackingEnabledKey, settings.locationTrackingEnabled);
    await prefs.setInt(_trackingIntervalMetersKey, settings.trackingIntervalMeters);
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
