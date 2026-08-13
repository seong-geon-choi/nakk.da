import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../location/presentation/location_provider.dart';
import '../../memo/presentation/memo_provider.dart';
import '../../memo/domain/models/memo_entry.dart';
import '../../../core/utils/media_scanner.dart';
import '../../../core/utils/exif_utils.dart';
import 'camera_ruler_screen.dart';

/// 잠금화면 위 카메라 전용 진입점(`cameraLockMain`)의 루트 앱.
///
/// 앱의 나머지 화면·데이터는 절대 로드하지 않고 카메라 화면만 띄운다.
/// 촬영 결과는 오늘 메모에 자동 첨부하고, 끝나면 네이티브 액티비티를 닫는다.
class CameraLockApp extends StatelessWidget {
  const CameraLockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: const _CameraLockHost(),
    );
  }
}

class _CameraLockHost extends ConsumerStatefulWidget {
  const _CameraLockHost();

  @override
  ConsumerState<_CameraLockHost> createState() => _CameraLockHostState();
}

class _CameraLockHostState extends ConsumerState<_CameraLockHost> {
  static const _channel = MethodChannel('nakkda/cameraLock');
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (_started) return;
    _started = true;
    try {
      final result = await Navigator.of(context).push<({String path, bool isVideo})>(
        MaterialPageRoute(builder: (_) => const CameraRulerScreen()),
      );
      if (result != null) {
        await _saveToToday(result);
      }
    } catch (_) {
      // 촬영/저장 실패 시에도 액티비티는 닫는다.
    } finally {
      await _finish();
    }
  }

  /// 촬영 결과를 오늘 날짜 메모에 첨부(음성 빠른저장과 동일한 방식).
  Future<void> _saveToToday(({String path, bool isVideo}) result) async {
    final settings = await ref.read(settingsProvider.future);
    final savePath = settings.savePath;

    // 사진은 영구 저장 위치로 복사, 동영상은 이미 저장된 경로 그대로 사용.
    String storedPath;
    DateTime timestamp = DateTime.now();
    double? lat;
    double? lng;
    if (result.isVideo) {
      storedPath = result.path;
    } else {
      final relPath = _mediaRelPath(settings.photoSavePath);
      storedPath = await saveToGallery(result.path, relativePath: relPath) ??
          result.path;
      timestamp = await readExifTimestamp(result.path) ?? timestamp;
      final gps = await readExifGps(result.path);
      lat = gps?.lat;
      lng = gps?.lng;
    }

    // GPS 폴백(현재 위치)
    if (lat == null) {
      final loc = ref.read(locationProvider).valueOrNull;
      lat = loc?.latitude ?? ref.read(locationProvider.notifier).cached?.latitude;
      lng = loc?.longitude ?? ref.read(locationProvider.notifier).cached?.longitude;
    }

    if (savePath.isEmpty) return; // 저장 폴더 미설정 시 갤러리 저장까지만
    final entry = MemoEntry(
      timestamp: timestamp,
      latitude: lat,
      longitude: lng,
      photoPath: result.isVideo ? null : storedPath,
      videoPath: result.isVideo ? storedPath : null,
    );
    final today = DateTime.now();
    await ref.read(memoRepositoryProvider).appendEntry(
        DateTime(today.year, today.month, today.day), entry, savePath);
  }

  /// photoSavePath에서 MediaStore 상대 경로를 추출(memo_input_sheet와 동일 규칙).
  String _mediaRelPath(String photoSavePath) {
    final lower = photoSavePath.toLowerCase();
    for (final marker in ['dcim/', 'pictures/', 'downloads/']) {
      final idx = lower.indexOf(marker);
      if (idx >= 0) return photoSavePath.substring(idx);
    }
    return 'DCIM/nakkda';
  }

  Future<void> _finish() async {
    try {
      await _channel.invokeMethod('finish');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // 카메라 화면을 push하기 전/후 잠깐 보이는 검은 배경.
    return const Scaffold(backgroundColor: Colors.black);
  }
}
