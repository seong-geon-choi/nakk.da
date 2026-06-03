import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../permission/presentation/permission_provider.dart';
import '../../../core/router/app_router.dart';

class PermissionGate extends ConsumerWidget {
  final Widget child;
  const PermissionGate({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(permissionStatusProvider);
    return statusAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (err, stack) => child,
      data: (statuses) {
        final allGranted = statuses.values.every((s) => s.isGranted);
        if (!allGranted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.go(AppRoutes.permission);
          });
        }
        return child;
      },
    );
  }
}
