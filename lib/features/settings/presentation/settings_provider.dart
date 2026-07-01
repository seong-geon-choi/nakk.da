import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/settings_repository_impl.dart';
import '../domain/models/app_settings.dart';
import '../domain/settings_repository.dart';
import '../../../core/services/saf_service.dart';
import '../../../core/services/tracking_service.dart';
import '../../backup/presentation/backup_provider.dart';

export '../domain/models/app_settings.dart'
    show
        WatermarkSettings,
        WatermarkBox,
        WatermarkLineType,
        WatermarkPosition,
        WatermarkAlign,
        WatermarkFont,
        WatermarkWeight,
        WatermarkTextContent,
        QuickLaunchMode,
        CommuteSoundMode,
        CommuteWindow,
        CommutePin,
        MemoComplexity,
        TackleField,
        VesselField;

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
    var settings = await repo.load();
    // 앱 시작 시 저장된 모드·민감도를 Android 서비스에 동기화
    await TrackingService()
        .setQuickLaunchMode(settings.quickLaunchMode.name, settings.shakeThresholdG);
    // 출퇴근 알림 추적 중이면, 네이티브가 사용자 스와이프로 중단됐는지 확인 후 정합화.
    // 중단됐으면 지도 아이콘을 끄고(active=false), 아니면 네이티브 재동기화.
    if (settings.commuteTracking) {
      final nativeActive = await TrackingService().commuteIsActive();
      if (nativeActive) {
        await TrackingService().commuteSync(_commuteConfig(settings));
      } else {
        settings = settings.copyWith(commuteAlarmActive: false);
        await repo.save(settings);
      }
    }
    return settings;
  }

  /// 앱 복귀 시 네이티브 감시 상태와 정합화.
  /// 대기 알림을 스와이프해 중단한 경우 지도 아이콘을 끈다(active=false).
  Future<void> reconcileCommuteActive() async {
    final c = state.valueOrNull;
    if (c == null || !c.commuteTracking) return;
    final nativeActive = await TrackingService().commuteIsActive();
    if (!nativeActive) {
      await _applyCommute(c.copyWith(commuteAlarmActive: false));
    }
  }

  // ── 지하철 출퇴근 알림 ──────────────────────────────
  Map<String, dynamic> _commuteConfig(AppSettings s) => {
        'enabled': s.commuteTracking,
        'radius': s.commuteRadius,
        'sound': s.commuteSoundMode.name,
        'pins': s.commutePins
            .map((p) => {'lat': p.lat, 'lng': p.lng, 'window': p.window.name})
            .toList(),
        'amStart': s.commuteAmStart,
        'amEnd': s.commuteAmEnd,
        'pmStart': s.commutePmStart,
        'pmEnd': s.commutePmEnd,
        'customStart': s.commuteCustomStart,
        'customEnd': s.commuteCustomEnd,
        'amEnabled': s.commuteAmEnabled,
        'pmEnabled': s.commutePmEnabled,
        'customEnabled': s.commuteCustomEnabled,
        'weekdaysOnly': s.commuteWeekdaysOnly,
      };

  Future<void> _applyCommute(AppSettings updated) async {
    await ref.read(settingsRepositoryProvider).save(updated);
    state = AsyncData(updated);
    if (updated.commuteTracking) {
      await TrackingService().commuteSync(_commuteConfig(updated));
    } else {
      await TrackingService().commuteStop();
    }
    // 변경된 출퇴근 설정을 드라이브에 자동 백업(백업 켜짐 + Wi-Fi일 때만)
    unawaited(ref.read(backupProvider.notifier).backupCommuteSettings());
  }

  /// 출퇴근 설정(지점 포함)을 백업용 JSON 맵으로 직렬화.
  Map<String, dynamic> commuteBackupJson() {
    final s = state.valueOrNull;
    if (s == null) return {};
    return {
      'enabled': s.commuteAlarmEnabled,
      'active': s.commuteAlarmActive,
      'radius': s.commuteRadius,
      'sound': s.commuteSoundMode.name,
      'pins': s.commutePins.map((p) => p.toJson()).toList(),
      'amStart': s.commuteAmStart,
      'amEnd': s.commuteAmEnd,
      'pmStart': s.commutePmStart,
      'pmEnd': s.commutePmEnd,
      'customStart': s.commuteCustomStart,
      'customEnd': s.commuteCustomEnd,
      'amEnabled': s.commuteAmEnabled,
      'pmEnabled': s.commutePmEnabled,
      'customEnabled': s.commuteCustomEnabled,
      'weekdaysOnly': s.commuteWeekdaysOnly,
    };
  }

  /// 백업 JSON에서 출퇴근 설정 복원(저장 + 서비스 재동기화).
  Future<void> restoreCommuteFromJson(Map<String, dynamic> j) async {
    final c = state.valueOrNull;
    if (c == null) return;
    final pins = (j['pins'] as List<dynamic>? ?? const [])
        .map((e) => CommutePin.fromJson(e as Map<String, dynamic>))
        .toList();
    await _applyCommute(c.copyWith(
      commuteAlarmEnabled: j['enabled'] as bool?,
      commuteAlarmActive: j['active'] as bool?,
      commuteRadius: j['radius'] as int?,
      commuteSoundMode: CommuteSoundMode.values.firstWhere(
        (e) => e.name == j['sound'],
        orElse: () => c.commuteSoundMode,
      ),
      commutePins: pins,
      commuteAmStart: j['amStart'] as int?,
      commuteAmEnd: j['amEnd'] as int?,
      commutePmStart: j['pmStart'] as int?,
      commutePmEnd: j['pmEnd'] as int?,
      commuteCustomStart: j['customStart'] as int?,
      commuteCustomEnd: j['customEnd'] as int?,
      commuteAmEnabled: j['amEnabled'] as bool?,
      commutePmEnabled: j['pmEnabled'] as bool?,
      commuteCustomEnabled: j['customEnabled'] as bool?,
      commuteWeekdaysOnly: j['weekdaysOnly'] as bool?,
    ));
  }

  Future<void> updateCommuteEnabled(bool value) async {
    final c = state.valueOrNull;
    if (c == null) return;
    // 켤 때는 활성 상태도 함께 켠다(지도 아이콘 기본 활성)
    await _applyCommute(c.copyWith(
        commuteAlarmEnabled: value, commuteAlarmActive: value ? true : null));
  }

  /// 지도 알람 아이콘: 추적 활성/일시중지 토글
  Future<void> updateCommuteActive(bool value) async {
    final c = state.valueOrNull;
    if (c == null) return;
    await _applyCommute(c.copyWith(commuteAlarmActive: value));
  }

  Future<void> updateCommuteRadius(int meters) async {
    final c = state.valueOrNull;
    if (c == null) return;
    await _applyCommute(c.copyWith(commuteRadius: meters));
  }

  Future<void> updateCommuteSound(CommuteSoundMode mode) async {
    final c = state.valueOrNull;
    if (c == null) return;
    await _applyCommute(c.copyWith(commuteSoundMode: mode));
  }

  Future<void> updateCommuteWindow({
    int? amStart,
    int? amEnd,
    int? pmStart,
    int? pmEnd,
    int? customStart,
    int? customEnd,
  }) async {
    final c = state.valueOrNull;
    if (c == null) return;
    await _applyCommute(c.copyWith(
      commuteAmStart: amStart,
      commuteAmEnd: amEnd,
      commutePmStart: pmStart,
      commutePmEnd: pmEnd,
      commuteCustomStart: customStart,
      commuteCustomEnd: customEnd,
    ));
  }

  Future<void> updateCommuteWindowEnabled({
    bool? am,
    bool? pm,
    bool? custom,
  }) async {
    final c = state.valueOrNull;
    if (c == null) return;
    await _applyCommute(c.copyWith(
      commuteAmEnabled: am,
      commutePmEnabled: pm,
      commuteCustomEnabled: custom,
    ));
  }

  Future<void> updateCommuteWeekdaysOnly(bool value) async {
    final c = state.valueOrNull;
    if (c == null) return;
    await _applyCommute(c.copyWith(commuteWeekdaysOnly: value));
  }

  Future<void> addCommutePin(double lat, double lng, {String label = ''}) async {
    final c = state.valueOrNull;
    if (c == null || c.commutePins.length >= 3) return;
    await _applyCommute(c.copyWith(commutePins: [
      ...c.commutePins,
      CommutePin(lat: lat, lng: lng, label: label),
    ]));
  }

  Future<void> removeCommutePin(int index) async {
    final c = state.valueOrNull;
    if (c == null || index < 0 || index >= c.commutePins.length) return;
    await _applyCommute(
        c.copyWith(commutePins: [...c.commutePins]..removeAt(index)));
  }

  Future<void> updateCommutePinLabel(int index, String label) async {
    final c = state.valueOrNull;
    if (c == null || index < 0 || index >= c.commutePins.length) return;
    final pins = [...c.commutePins];
    final p = pins[index];
    pins[index] =
        CommutePin(lat: p.lat, lng: p.lng, label: label, window: p.window);
    await _applyCommute(c.copyWith(commutePins: pins));
  }

  Future<void> updateCommutePinWindow(int index, CommuteWindow window) async {
    final c = state.valueOrNull;
    if (c == null || index < 0 || index >= c.commutePins.length) return;
    final pins = [...c.commutePins];
    final p = pins[index];
    pins[index] =
        CommutePin(lat: p.lat, lng: p.lng, label: p.label, window: window);
    await _applyCommute(c.copyWith(commutePins: pins));
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

  Future<void> updateAutoLocationOnFirstEntry(bool value) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final updated = current.copyWith(autoLocationOnFirstEntry: value);
    await ref.read(settingsRepositoryProvider).save(updated);
    state = AsyncData(updated);
  }

  Future<void> updateMemoComplexity(MemoComplexity mode) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final updated = current.copyWith(memoComplexity: mode);
    await ref.read(settingsRepositoryProvider).save(updated);
    state = AsyncData(updated);
  }

  // ── 태클 프리셋 ───────────────────────────────────────
  AppSettings _copyTackle(
          AppSettings c, TackleField f, List<String> list) =>
      switch (f) {
        TackleField.rod => c.copyWith(tackleRods: list),
        TackleField.reel => c.copyWith(tackleReels: list),
        TackleField.line => c.copyWith(tackleLines: list),
        TackleField.rig => c.copyWith(tackleRigs: list),
      };

  /// 태클 프리셋 추가(중복·공백 무시, 최신순 맨 앞).
  Future<void> addTacklePreset(TackleField field, String value) async {
    final c = state.valueOrNull;
    if (c == null) return;
    final v = value.trim();
    if (v.isEmpty || c.tacklePresetsFor(field).contains(v)) return;
    final updated = _copyTackle(c, field, [v, ...c.tacklePresetsFor(field)]);
    await ref.read(settingsRepositoryProvider).save(updated);
    state = AsyncData(updated);
  }

  Future<void> removeTacklePreset(TackleField field, String value) async {
    final c = state.valueOrNull;
    if (c == null) return;
    final updated = _copyTackle(
        c, field, c.tacklePresetsFor(field).where((s) => s != value).toList());
    await ref.read(settingsRepositoryProvider).save(updated);
    state = AsyncData(updated);
  }

  // ── 선사 프리셋 ───────────────────────────────────────
  AppSettings _copyVessel(AppSettings c, VesselField f, List<String> list) =>
      switch (f) {
        VesselField.name => c.copyWith(vesselNames: list),
        VesselField.port => c.copyWith(vesselPorts: list),
        VesselField.point => c.copyWith(vesselPoints: list),
        VesselField.fishType => c.copyWith(vesselFishTypes: list),
      };

  Future<void> addVesselPreset(VesselField field, String value) async {
    final c = state.valueOrNull;
    if (c == null) return;
    final v = value.trim();
    if (v.isEmpty || c.vesselPresetsFor(field).contains(v)) return;
    final updated = _copyVessel(c, field, [v, ...c.vesselPresetsFor(field)]);
    await ref.read(settingsRepositoryProvider).save(updated);
    state = AsyncData(updated);
  }

  Future<void> removeVesselPreset(VesselField field, String value) async {
    final c = state.valueOrNull;
    if (c == null) return;
    final updated = _copyVessel(
        c, field, c.vesselPresetsFor(field).where((s) => s != value).toList());
    await ref.read(settingsRepositoryProvider).save(updated);
    state = AsyncData(updated);
  }

  Future<void> updateShareEnabled(bool value) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final updated = current.copyWith(shareEnabled: value);
    await ref.read(settingsRepositoryProvider).save(updated);
    state = AsyncData(updated);
  }

  Future<void> updateAdsEnabled(bool value) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final updated = current.copyWith(adsEnabled: value);
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

  /// 활성 템플릿 슬롯의 워터마크를 갱신.
  Future<void> updateWatermark(WatermarkSettings watermark) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final templates = [...current.watermarkTemplates];
    templates[current.watermarkTemplateIndex] = watermark;
    final updated = current.copyWith(watermarkTemplates: templates);
    await ref.read(settingsRepositoryProvider).save(updated);
    state = AsyncData(updated);
  }

  /// 활성 워터마크 템플릿 선택(0~2). 즉시 적용됨.
  /// 워터마크 사용(enabled)은 마스터 스위치로 취급 → 전환 시 유지(디자인만 교체).
  Future<void> selectWatermarkTemplate(int index) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final i = index.clamp(0, 2);
    final wasEnabled = current.watermark.enabled;
    final templates = [...current.watermarkTemplates];
    templates[i] = templates[i].copyWith(enabled: wasEnabled);
    final updated = current.copyWith(
        watermarkTemplates: templates, watermarkTemplateIndex: i);
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
    await TrackingService().setQuickLaunchMode(mode.name, updated.shakeThresholdG);
  }

  /// 흔들기 감지 가속도 임계값(G) 변경. 2.5~5.0으로 제한하고 즉시 네이티브에 반영.
  Future<void> updateShakeThresholdG(double value) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final clamped = value.clamp(2.5, 5.0);
    final updated = current.copyWith(shakeThresholdG: clamped);
    await ref.read(settingsRepositoryProvider).save(updated);
    state = AsyncData(updated);
    await TrackingService()
        .setQuickLaunchMode(updated.quickLaunchMode.name, clamped);
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
