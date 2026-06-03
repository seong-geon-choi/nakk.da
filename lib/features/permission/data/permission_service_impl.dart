import 'package:permission_handler/permission_handler.dart';
import '../domain/permission_service.dart';

class PermissionServiceImpl implements PermissionService {
  static final List<Permission> _required = [
    Permission.microphone,
    Permission.locationWhenInUse,
    Permission.camera,
    Permission.photos,
    Permission.notification,
    // manageExternalStorage는 시스템 설정 페이지가 필요해서 requestAll에서 제외,
    // checkAll에는 포함해 상태 표시
    Permission.manageExternalStorage,
  ];

  static final List<Permission> _requestable = [
    Permission.microphone,
    Permission.locationWhenInUse,
    Permission.camera,
    Permission.photos,
    Permission.notification,
  ];

  @override
  Future<Map<Permission, PermissionStatus>> checkAll() async {
    final result = <Permission, PermissionStatus>{};
    for (final p in _required) {
      result[p] = await p.status;
    }
    return result;
  }

  @override
  Future<Map<Permission, PermissionStatus>> requestAll() async {
    return await _requestable.request();
  }

  @override
  Future<bool> get areAllGranted async {
    final statuses = await checkAll();
    return statuses.values.every((s) => s.isGranted);
  }
}
