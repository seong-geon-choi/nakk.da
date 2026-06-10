import 'package:permission_handler/permission_handler.dart';
import '../domain/permission_service.dart';

class PermissionServiceImpl implements PermissionService {
  static final List<Permission> _required = [
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
    final result = await _required.request();
    return Map.fromEntries(result.entries.where((e) => _required.contains(e.key)));
  }

  @override
  Future<bool> get areAllGranted async {
    final statuses = await checkAll();
    return statuses.values.every((s) => s.isGranted);
  }
}
