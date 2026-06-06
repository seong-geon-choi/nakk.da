import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';

class GalleryPickerScreen extends StatefulWidget {
  const GalleryPickerScreen({super.key});

  @override
  State<GalleryPickerScreen> createState() => _GalleryPickerScreenState();
}

class _GalleryPickerScreenState extends State<GalleryPickerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  bool _loading = true;
  _PermState _permState = _PermState.ok;
  List<AssetEntity> _assets = [];

  static const _types = [RequestType.common, RequestType.image, RequestType.video];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(_onTabChanged);
    _loadAssets(RequestType.common);
  }

  @override
  void dispose() {
    _tabCtrl.removeListener(_onTabChanged);
    _tabCtrl.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabCtrl.indexIsChanging) return;
    _loadAssets(_types[_tabCtrl.index]);
  }

  Future<void> _loadAssets(RequestType type) async {
    setState(() { _loading = true; _assets = []; _permState = _PermState.ok; });

    final perm = await PhotoManager.requestPermissionExtend();

    // 완전 거부 → 설정 안내
    if (perm == PermissionState.denied) {
      setState(() { _permState = _PermState.denied; _loading = false; });
      return;
    }

    // 부분 접근(limited) + 동영상 탭 → 동영상 권한 별도 확인
    if (perm == PermissionState.limited && type == RequestType.video) {
      final videoStatus = await Permission.videos.status;
      if (!videoStatus.isGranted) {
        final req = await Permission.videos.request();
        if (!req.isGranted) {
          setState(() { _permState = _PermState.videoOnly; _loading = false; });
          return;
        }
        // 권한 획득 후 photo_manager 재초기화
        await PhotoManager.clearFileCache();
      }
    }

    try {
      final albums = await PhotoManager.getAssetPathList(type: type, onlyAll: true);
      if (albums.isEmpty) {
        // limited 모드 + 전체/동영상 탭에서 비어있으면 안내
        if (perm == PermissionState.limited && type != RequestType.image) {
          setState(() { _permState = _PermState.limited; _loading = false; });
          return;
        }
        setState(() { _loading = false; });
        return;
      }
      final assets = await albums.first.getAssetListPaged(page: 0, size: 300);
      if (mounted) setState(() { _assets = assets; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _select(AssetEntity asset) async {
    final file = await asset.file;
    if (file == null || !mounted) return;
    Navigator.of(context).pop<({String path, bool isVideo})>(
      (path: file.path, isVideo: asset.type == AssetType.video),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('갤러리'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: '전체'),
            Tab(text: '사진'),
            Tab(text: '동영상'),
          ],
        ),
      ),
      body: switch (_permState) {
        _PermState.denied => _PermissionView(
            message: '사진/동영상 접근 권한이 필요합니다.\n설정에서 권한을 허용해 주세요.',
            onSettings: _openSettings,
            onRetry: () => _loadAssets(_types[_tabCtrl.index]),
          ),
        _PermState.videoOnly => _PermissionView(
            message: '동영상 접근 권한이 없습니다.\n설정 → 앱 권한에서\n"동영상"을 허용해 주세요.',
            onSettings: _openSettings,
            onRetry: () => _loadAssets(_types[_tabCtrl.index]),
          ),
        _PermState.limited => _PermissionView(
            message: '일부 사진만 접근 가능한 상태입니다.\n설정에서 "모두 허용"으로 변경하면\n전체 미디어를 볼 수 있습니다.',
            onSettings: _openSettings,
            onRetry: () => _loadAssets(_types[_tabCtrl.index]),
            isWarning: true,
          ),
        _PermState.ok => _loading
            ? const Center(child: CircularProgressIndicator())
            : _assets.isEmpty
                ? const Center(child: Text('항목이 없습니다'))
                : GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 2,
                      mainAxisSpacing: 2,
                    ),
                    itemCount: _assets.length,
                    itemBuilder: (ctx, i) => _AssetTile(
                      asset: _assets[i],
                      onTap: () => _select(_assets[i]),
                    ),
                  ),
      },
    );
  }

  Future<void> _openSettings() async {
    await openAppSettings();
  }
}

enum _PermState { ok, denied, videoOnly, limited }

class _PermissionView extends StatelessWidget {
  final String message;
  final VoidCallback onSettings;
  final VoidCallback onRetry;
  final bool isWarning;

  const _PermissionView({
    required this.message,
    required this.onSettings,
    required this.onRetry,
    this.isWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isWarning ? Icons.info_outline : Icons.lock_outline,
              size: 48,
              color: isWarning
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.6),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onSettings,
              icon: const Icon(Icons.settings_outlined),
              label: const Text('설정 열기'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onRetry,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssetTile extends StatelessWidget {
  final AssetEntity asset;
  final VoidCallback onTap;

  const _AssetTile({required this.asset, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<Uint8List?>(
            future: asset.thumbnailDataWithSize(const ThumbnailSize(200, 200)),
            builder: (ctx, snap) {
              if (snap.data != null) {
                return Image.memory(snap.data!, fit: BoxFit.cover);
              }
              return const ColoredBox(color: Color(0xFFE0E0E0));
            },
          ),
          if (asset.type == AssetType.video)
            const Positioned(
              right: 4,
              bottom: 4,
              child: Icon(Icons.play_circle_fill, color: Colors.white, size: 20,
                  shadows: [Shadow(blurRadius: 4)]),
            ),
        ],
      ),
    );
  }
}
