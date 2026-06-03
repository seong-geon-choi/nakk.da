import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../data/photo_service_impl.dart';
import '../domain/photo_service.dart';
import '../../memo/domain/models/memo_entry.dart';
import '../../memo/presentation/memo_provider.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../location/presentation/location_provider.dart';
import '../../../core/utils/media_scanner.dart';

final photoServiceProvider = Provider<PhotoService>(
  (ref) => PhotoServiceImpl(),
);

final photoProvider = AsyncNotifierProvider<PhotoNotifier, void>(
  PhotoNotifier.new,
);

class PhotoNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<bool> pickAndSave(PhotoSource source) async {
    state = const AsyncLoading();
    try {
      final settings = await ref.read(settingsProvider.future);
      final tempPath = await ref.read(photoServiceProvider).pickImage(source: source);
      if (tempPath == null) {
        state = const AsyncData(null);
        return false;
      }
      final now = DateTime.now();
      // 갤러리 사진: 캐시 → 앱 전용 외부 저장소로 복사 (캐시 삭제 시 유실 방지)
      // 카메라 사진: MediaStore에 등록해 갤러리에 표시
      final String? savedPath;
      if (source == PhotoSource.gallery) {
        savedPath = await copyGalleryPhotoToAppStorage(tempPath);
      } else {
        savedPath = await saveToGallery(
          tempPath,
          relativePath: _mediaRelativePath(settings.photoSavePath),
        );
      }
      if (savedPath == null) {
        state = const AsyncData(null);
        return false;
      }
      final gps = await _bestGps();
      final entry = MemoEntry(
        timestamp: now,
        latitude: gps?.$1,
        longitude: gps?.$2,
        photoPath: savedPath,
      );
      await ref.read(todayFileProvider.notifier).addEntry(entry);
      state = const AsyncData(null);
      return true;
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
      return false;
    }
  }


  // CameraRulerScreen에서 직접 찍은 사진을 저장 (fishLength 포함)
  Future<bool> saveFromPath(String path, {double? fishLength}) async {
    state = const AsyncLoading();
    try {
      final settings = await ref.read(settingsProvider.future);
      final now = DateTime.now();
      final savedPath = await saveToGallery(
        path,
        relativePath: _mediaRelativePath(settings.photoSavePath),
      );
      if (savedPath == null) {
        state = const AsyncData(null);
        return false;
      }
      final gps = await _bestGps();
      final entry = MemoEntry(
        timestamp: now,
        latitude: gps?.$1,
        longitude: gps?.$2,
        photoPath: savedPath,
        fishLength: fishLength,
      );
      await ref.read(todayFileProvider.notifier).addEntry(entry);
      state = const AsyncData(null);
      return true;
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
      return false;
    }
  }

  /// locationProvider → locationService 캐시 → Geolocator 최근 위치 순 fallback
  Future<(double, double)?> _bestGps() async {
    final loc = ref.read(locationProvider).valueOrNull
        ?? ref.read(locationProvider.notifier).cached;
    if (loc?.latitude != null) return (loc!.latitude!, loc.longitude!);
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null) return (pos.latitude, pos.longitude);
    } catch (_) {}
    return null;
  }

  /// photoSavePath (절대경로)에서 MediaStore RELATIVE_PATH 추출.
  /// "/storage/emulated/0/DCIM/nakkda" → "DCIM/nakkda"
  String _mediaRelativePath(String photoSavePath) {
    final lower = photoSavePath.toLowerCase();
    for (final marker in ['dcim/', 'pictures/', 'downloads/']) {
      final idx = lower.indexOf(marker);
      if (idx >= 0) return photoSavePath.substring(idx);
    }
    return 'DCIM/nakkda';
  }
}
