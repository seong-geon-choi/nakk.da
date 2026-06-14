import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/settings_repository_impl.dart';
import '../domain/models/app_settings.dart';
import '../domain/settings_repository.dart';
import '../../../core/services/saf_service.dart';
import '../../../core/services/tracking_service.dart';

export '../domain/models/app_settings.dart'
    show
        WatermarkSettings,
        WatermarkLine,
        WatermarkLineType,
        WatermarkPosition,
        WatermarkAlign,
        WatermarkFont,
        QuickLaunchMode;

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
    final settings = await repo.load();
    // 앱 시작 시 저장된 모드를 Android 서비스에 동기화
    await TrackingService().setQuickLaunchMode(settings.quickLaunchMode.name);
    return settings;
  }

  final _saf = SafService();

  /// SAF 폴더 피커를 열고 선택된 폴더를 savePath로 저장
  Future<bool> pickSaveFolder() async {
    final current = state.valueOrNull;
    final hint = current?.saveDisplayPath.isNotEmpty == true
        ? current!.saveDisplayPath
        : SettingsRepositoryImpl.defaultMemoDisplayPath;
    // 첫 설정(저장 경로 없음)이면 기본 폴더(Documents/nakkda)를 미리 생성해
    // 픽커가 해당 폴더에서 열리도록 → 사용자는 '이 폴더 사용'만 누르면 됨
    if (current != null && current.savePath.isEmpty) {
      final rel = SettingsRepositoryImpl.defaultMemoDisplayPath
          .replaceFirst('/storage/emulated/0/', '');
      await _saf.ensureFolderInPublicStorage(rel);
    }
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

  Future<void> updateShowTrackingButton(bool show) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final updated = current.copyWith(showTrackingButton: show);
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

  Future<void> updateShowCatchInput(bool value) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final updated = current.copyWith(showCatchInput: value);
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

  /// 어종 추가 (중복·공백 무시). 새 항목은 목록 맨 앞에 추가.
  Future<void> addFishSpecies(String species) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final name = species.trim();
    if (name.isEmpty || current.fishSpecies.contains(name)) return;
    final updated = current.copyWith(fishSpecies: [name, ...current.fishSpecies]);
    await ref.read(settingsRepositoryProvider).save(updated);
    state = AsyncData(updated);
  }

  Future<void> removeFishSpecies(String species) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final updated = current.copyWith(
      fishSpecies: current.fishSpecies.where((s) => s != species).toList(),
      hiddenFishSpecies:
          current.hiddenFishSpecies.where((s) => s != species).toList(),
    );
    await ref.read(settingsRepositoryProvider).save(updated);
    state = AsyncData(updated);
  }

  /// 어종의 메모 드롭다운 표시여부 토글. 탐지(음성/메모)에는 영향 없음.
  Future<void> setFishSpeciesVisible(String species, bool visible) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final hidden = [...current.hiddenFishSpecies];
    if (visible) {
      hidden.remove(species);
    } else if (!hidden.contains(species)) {
      hidden.add(species);
    }
    final updated = current.copyWith(hiddenFishSpecies: hidden);
    await ref.read(settingsRepositoryProvider).save(updated);
    state = AsyncData(updated);
  }

  Future<void> updateQuickLaunchMode(QuickLaunchMode mode) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final updated = current.copyWith(quickLaunchMode: mode);
    await ref.read(settingsRepositoryProvider).save(updated);
    state = AsyncData(updated);
    await TrackingService().setQuickLaunchMode(mode.name);
  }

  Future<void> updateTrackingIntervalMeters(int value) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final updated = current.copyWith(trackingIntervalMeters: value.clamp(30, 1000));
    await ref.read(settingsRepositoryProvider).save(updated);
    state = AsyncData(updated);
  }

  Future<void> updateDriveBackup({
    bool? enabled,
    bool? includeMedia,
    DateTime? lastSyncAt,
    bool? lastSyncSuccess,
    bool clearLastSync = false,
  }) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final updated = current.copyWith(
      driveBackupEnabled: enabled,
      driveBackupIncludeMedia: includeMedia,
      lastSyncAt: lastSyncAt,
      lastSyncSuccess: lastSyncSuccess,
      clearLastSync: clearLastSync,
    );
    await ref.read(settingsRepositoryProvider).save(updated);
    state = AsyncData(updated);
  }

  Future<void> updateLocationFabPosition(double right, double bottom) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final updated =
        current.copyWith(locationFabRight: right, locationFabBottom: bottom);
    await ref.read(settingsRepositoryProvider).save(updated);
    state = AsyncData(updated);
  }

  Future<void> updateTrackingFabPosition(double right, double bottom) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final updated =
        current.copyWith(trackingFabRight: right, trackingFabBottom: bottom);
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
