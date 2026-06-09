import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/settings_repository_impl.dart';
import '../domain/models/app_settings.dart';
import '../domain/settings_repository.dart';
import '../../../core/services/saf_service.dart';

export '../domain/models/app_settings.dart'
    show
        WatermarkSettings,
        WatermarkLine,
        WatermarkLineType,
        WatermarkPosition,
        WatermarkAlign,
        WatermarkFont;

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepositoryImpl(),
);

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final repo = ref.read(settingsRepositoryProvider);
    return repo.load();
  }

  final _saf = SafService();

  /// SAF 폴더 피커를 열고 선택된 폴더를 savePath로 저장
  Future<bool> pickSaveFolder() async {
    final current = state.valueOrNull;
    final hint = current?.saveDisplayPath.isNotEmpty == true
        ? current!.saveDisplayPath
        : SettingsRepositoryImpl.defaultMemoDisplayPath;
    final picked = await _saf.pickFolder(initialPath: hint);
    if (picked == null) return false;
    if (current == null) return false;
    final updated = current.copyWith(
      savePath: picked.uri,
      saveDisplayPath: picked.displayPath,
    );
    await ref.read(settingsRepositoryProvider).save(updated);
    state = AsyncData(updated);
    return true;
  }

  Future<void> updateSavePath(String path) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final updated = current.copyWith(savePath: path);
    await ref.read(settingsRepositoryProvider).save(updated);
    state = AsyncData(updated);
  }

  Future<bool> pickPhotoSaveFolder() async {
    final current = state.valueOrNull;
    final picked = await _saf.pickFolder(initialPath: current?.photoSavePath);
    if (picked == null) return false;
    if (current == null) return false;
    final updated = current.copyWith(photoSavePath: picked.displayPath);
    await ref.read(settingsRepositoryProvider).save(updated);
    state = AsyncData(updated);
    return true;
  }

  Future<void> updatePhotoSavePath(String path) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final updated = current.copyWith(photoSavePath: path);
    await ref.read(settingsRepositoryProvider).save(updated);
    state = AsyncData(updated);
  }

  Future<void> updateAutoSaveVoice(bool value) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final updated = current.copyWith(autoSaveVoice: value);
    await ref.read(settingsRepositoryProvider).save(updated);
    state = AsyncData(updated);
  }

  Future<void> updateShowLocationButton(bool show) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final updated = current.copyWith(showLocationButton: show);
    await ref.read(settingsRepositoryProvider).save(updated);
    state = AsyncData(updated);
  }

  Future<void> updateShowAddressInMemoName(bool value) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final updated = current.copyWith(showAddressInMemoName: value);
    await ref.read(settingsRepositoryProvider).save(updated);
    state = AsyncData(updated);
  }

  Future<void> updateWatermark(WatermarkSettings watermark) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final updated = current.copyWith(watermark: watermark);
    await ref.read(settingsRepositoryProvider).save(updated);
    state = AsyncData(updated);
  }

  Future<void> updateLocationTrackingEnabled(bool value) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final updated = current.copyWith(locationTrackingEnabled: value);
    await ref.read(settingsRepositoryProvider).save(updated);
    state = AsyncData(updated);
  }

  Future<void> updateTrackingIntervalMeters(int value) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final updated = current.copyWith(trackingIntervalMeters: value.clamp(30, 1000));
    await ref.read(settingsRepositoryProvider).save(updated);
    state = AsyncData(updated);
  }

  Future<void> updateKhoaApiKey(String? key) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final trimmed = key?.trim();
    final updated = trimmed == null || trimmed.isEmpty
        ? current.copyWith(clearKhoaApiKey: true)
        : current.copyWith(khoaApiKey: trimmed);
    await ref.read(settingsRepositoryProvider).save(updated);
    state = AsyncData(updated);
  }
}
