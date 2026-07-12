import 'package:permission_handler/permission_handler.dart';

abstract interface class PermissionService {
  Future<Map<Permission, PermissionStatus>> checkAll();
  Future<Map<Permission, PermissionStatus>> requestAll({bool includeLocation = true});
  Future<bool> get areAllGranted;
}
