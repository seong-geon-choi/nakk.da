import 'package:permission_handler/permission_handler.dart';
import '../domain/permission_service.dart';

class PermissionServiceImpl implements PermissionService {
  static final List<Permission> _required = [
    Permission.microphone,
    Permission.locationWhenInUse,
    Permission.camera,
    Permission.photos,
    Permission.videos,
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
  Future<Map<Permission, PermissionStatus>> requestAll({bool includeLocation = true}) async {
    // 위치 명시적 공개에 동의하지 않은 경우 위치 권한은 요청하지 않는다.
    final targets = includeLocation
        ? _required
        : _required.where((p) => p != Permission.locationWhenInUse).toList();
    final result = await targets.request();
    return Map.fromEntries(result.entries.where((e) => _required.contains(e.key)));
  }

  @override
  Future<bool> get areAllGranted async {
    final statuses = await checkAll();
    return statuses.values.every((s) => s.isGranted);
  }
}
