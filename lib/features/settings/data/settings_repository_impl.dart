import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models/app_settings.dart';
import '../domain/settings_repository.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  static const _savePathKey = 'save_path';
  static const _photoSavePathKey = 'photo_save_path';
  static const _showLocationButtonKey = 'show_location_button';
  static const _autoSaveVoiceKey = 'auto_save_voice';
  static const _khoaApiKeyKey = 'khoa_api_key';
  static const _watermarkKey = 'watermark_settings';

  @override
  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    // 구 패키지 경로(vo_rec) 또는 미설정이면 기본값으로 재계산
    final rawPath = prefs.getString(_savePathKey);
    final savePath = (rawPath == null ||
            rawPath.contains('vo_rec') ||
            rawPath.contains('/DCIM/nakkda') ||
            rawPath.contains('/Android/data/com.nakkda.nakkda/files'))
        ? await _defaultSavePath()
        : rawPath;
    final storedPhotoPath = prefs.getString(_photoSavePathKey);
    final photoSavePath = (storedPhotoPath == null || storedPhotoPath.contains('/Pictures/'))
        ? await _defaultPhotoSavePath()
        : storedPhotoPath;
    final showLocationButton = prefs.getBool(_showLocationButtonKey) ?? true;
    final autoSaveVoice = prefs.getBool(_autoSaveVoiceKey) ?? false;
    final khoaApiKey = prefs.getString(_khoaApiKeyKey);
    final wmJson = prefs.getString(_watermarkKey);
    final watermark = wmJson != null
        ? WatermarkSettings.fromJson(
            jsonDecode(wmJson) as Map<String, dynamic>)
        : WatermarkSettings();
    return AppSettings(
      savePath: savePath,
      photoSavePath: photoSavePath,
      showLocationButton: showLocationButton,
      autoSaveVoice: autoSaveVoice,
      khoaApiKey: khoaApiKey,
      watermark: watermark,
    );
  }

  @override
  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savePathKey, settings.savePath);
    await prefs.setString(_photoSavePathKey, settings.photoSavePath);
    await prefs.setBool(_showLocationButtonKey, settings.showLocationButton);
    await prefs.setBool(_autoSaveVoiceKey, settings.autoSaveVoice);
    if (settings.khoaApiKey != null) {
      await prefs.setString(_khoaApiKeyKey, settings.khoaApiKey!);
    } else {
      await prefs.remove(_khoaApiKeyKey);
    }
    await prefs.setString(
        _watermarkKey, jsonEncode(settings.watermark.toJson()));
  }

  Future<String> _defaultSavePath() async {
    final appDir = await getExternalStorageDirectory();
    if (appDir != null) {
      final base = appDir.path.split('/Android/').first;
      return '$base/Documents/nakkda';
    }
    return '${(await getApplicationDocumentsDirectory()).path}/nakkda';
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
