import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../location/presentation/location_provider.dart';
import 'camera_ruler_screen.dart';

/// 잠금화면 위 카메라 전용 진입점(`cameraLockMain`)의 루트 앱.
///
/// 이 액티비티(CameraLockActivity)는 앱 격리를 위해 별도 Flutter 엔진을 쓰므로,
/// 갤러리 저장·메모 파일 쓰기용 커스텀 MethodChannel(media/saf)이 없다. 그래서
/// 촬영 결과를 직접 저장하지 않고 대기열(SharedPreferences)에 넣고, 채널이 모두
/// 갖춰진 메인 앱이 열릴 때(홈 화면 resume/콜드스타트) 갤러리 저장 + 오늘 메모
/// 등록을 처리한다(음성 결과 전달과 동일한 패턴).
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

/// 메인 앱과 공유하는 흔들기 촬영 대기열 prefs 키.
const String kPendingShakePhotosKey = 'pending_shake_photos';

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
        await _queuePhoto(result);
      }
    } catch (_) {
      // 촬영/대기열 저장 실패 시에도 액티비티는 닫는다.
    } finally {
      await _finish();
    }
  }

  /// 촬영 결과를 영구 위치로 옮기고 대기열(prefs)에 추가한다.
  Future<void> _queuePhoto(({String path, bool isVideo}) result) async {
    // 캡처 파일은 캐시에 있어 지워질 수 있으므로 앱 문서 폴더로 복사해 보존한다.
    final docs = await getApplicationDocumentsDirectory();
    final pendingDir = Directory('${docs.path}/pending_shake');
    await pendingDir.create(recursive: true);
    final ts = DateTime.now();
    final ext = result.path.contains('.')
        ? result.path.split('.').last
        : (result.isVideo ? 'mp4' : 'jpg');
    final dest = '${pendingDir.path}/${ts.millisecondsSinceEpoch}.$ext';
    try {
      await File(result.path).copy(dest);
    } catch (_) {
      return;
    }

    // GPS는 현재 위치(있으면)로 기록. 없으면 null.
    final loc = ref.read(locationProvider).valueOrNull;
    final cached = ref.read(locationProvider.notifier).cached;
    final lat = loc?.latitude ?? cached?.latitude;
    final lng = loc?.longitude ?? cached?.longitude;

    final prefs = await SharedPreferences.getInstance();
    // 메인 앱이 처리하며 큐를 비웠을 수 있으니 디스크 최신 상태를 읽고 append한다.
    await prefs.reload();
    final list = prefs.getStringList(kPendingShakePhotosKey) ?? [];
    list.add(jsonEncode({
      'path': dest,
      'isVideo': result.isVideo,
      'ts': ts.toIso8601String(),
      'lat': lat,
      'lng': lng,
    }));
    await prefs.setStringList(kPendingShakePhotosKey, list);
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
