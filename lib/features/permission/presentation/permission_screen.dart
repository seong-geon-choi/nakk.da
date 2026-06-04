import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/router/app_router.dart';
import '../../../features/settings/presentation/settings_provider.dart';
import 'permission_provider.dart';

class PermissionScreen extends ConsumerStatefulWidget {
  const PermissionScreen({super.key});

  @override
  ConsumerState<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends ConsumerState<PermissionScreen> {
  bool _folderPicked = false;

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(permissionStatusProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Text(
                '낚.다',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '앱을 사용하려면 아래 권한과 저장 폴더 설정이 필요합니다',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFolderItem(context),
                      const SizedBox(height: 16),
                      ..._permissionItems(context, statusAsync),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                onPressed: () async {
                  await ref.read(permissionStatusProvider.notifier).requestAll();
                  if (!context.mounted) return;
                  if (!_folderPicked) {
                    final picked = await ref.read(settingsProvider.notifier).pickSaveFolder();
                    if (mounted) setState(() => _folderPicked = picked);
                  }
                  if (!context.mounted) return;
                  await _markDoneAndGo(context);
                },
                child: const Text('권한 허용하기', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 12),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () async {
                  if (!context.mounted) return;
                  await _markDoneAndGo(context);
                },
                child: const Text('나중에 하기'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFolderItem(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 0),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.folder_outlined, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('메모 저장 폴더',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                Text('메모 파일을 저장할 폴더를 선택합니다',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Icon(
            _folderPicked ? Icons.check_circle : Icons.radio_button_unchecked,
            color: _folderPicked ? Colors.green : Colors.grey,
            size: 22,
          ),
        ],
      ),
    );
  }

  List<Widget> _permissionItems(
      BuildContext context, AsyncValue<Map<Permission, PermissionStatus>> statusAsync) {
    final items = [
      (Permission.microphone, Icons.mic, '마이크', '음성 메모 녹음에 필요합니다'),
      (Permission.locationWhenInUse, Icons.location_on, '위치', 'GPS 좌표를 메모에 기록합니다'),
      (Permission.camera, Icons.camera_alt, '카메라', '사진 촬영 및 첨부에 필요합니다'),
      (Permission.photos, Icons.photo_library_outlined, '사진', '갤러리에서 사진을 선택합니다'),
      (Permission.notification, Icons.notifications_outlined, '알림', '음성 메모 상태를 알림으로 표시합니다'),
    ];
    return items.map((item) => _buildPermItem(context, statusAsync, item)).toList();
  }

  Widget _buildPermItem(
      BuildContext context,
      AsyncValue<Map<Permission, PermissionStatus>> statusAsync,
      (Permission, IconData, String, String) item) {
    final (perm, icon, label, desc) = item;
    final isGranted = statusAsync.valueOrNull?[perm]?.isGranted ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                Text(desc, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Icon(
            isGranted ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isGranted ? Colors.green : Colors.grey,
            size: 22,
          ),
        ],
      ),
    );
  }

  Future<void> _markDoneAndGo(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('first_launch_done', true);
    if (context.mounted) context.go(AppRoutes.home);
  }
}
