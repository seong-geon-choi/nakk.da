import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../data/permission_service_impl.dart';
import '../domain/permission_service.dart';

final permissionServiceProvider = Provider<PermissionService>(
  (ref) => PermissionServiceImpl(),
);

final permissionStatusProvider =
    AsyncNotifierProvider<PermissionStatusNotifier, Map<Permission, PermissionStatus>>(
  PermissionStatusNotifier.new,
);

class PermissionStatusNotifier
    extends AsyncNotifier<Map<Permission, PermissionStatus>> {
  @override
  Future<Map<Permission, PermissionStatus>> build() async {
    return ref.read(permissionServiceProvider).checkAll();
  }

  Future<void> requestAll() async {
    state = const AsyncLoading();
    final result =
        await ref.read(permissionServiceProvider).requestAll();
    state = AsyncData(result);
    // RECORD_AUDIO가 허가되면 볼륨버튼 음성 서비스 기동 시도
    if (result[Permission.microphone]?.isGranted == true) {
      try {
        await const MethodChannel('com.nakkda.nakkda/accessibility')
            .invokeMethod('startVoiceService');
      } catch (_) {}
    }
  }

  bool get areAllGranted =>
      state.valueOrNull?.values.every((s) => s.isGranted) ?? false;
}
