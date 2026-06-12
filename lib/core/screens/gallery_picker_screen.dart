import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';

class _DateGroup {
  final String label;
  final List<AssetEntity> assets;
  _DateGroup(this.label, this.assets);
}

class GalleryPickerScreen extends StatefulWidget {
  const GalleryPickerScreen({super.key});

  @override
  State<GalleryPickerScreen> createState() => _GalleryPickerScreenState();
}

class _GalleryPickerScreenState extends State<GalleryPickerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  late final ScrollController _scrollCtrl;

  List<AssetEntity> _assets = [];
  List<_DateGroup> _groups = [];
  AssetPathEntity? _album;
  int _page = 0;
  bool _hasMore = true;

  bool _loading = true;
  bool _loadingMore = false;
  bool _permDenied = false;

  bool _selectMode = false;
  final Set<String> _selected = {};

  final Map<RequestType, int> _counts = {};

  static const _pageSize = 80;
  static const _types = [RequestType.common, RequestType.image, RequestType.video];

  final _filterOption = FilterOptionGroup(
    orders: const [OrderOption(type: OrderOptionType.createDate, asc: false)],
  );

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(_onTabChanged);
    _scrollCtrl = ScrollController()..addListener(_onScroll);
    _loadAssets(RequestType.common);
  }

  @override
  void dispose() {
    _tabCtrl.removeListener(_onTabChanged);
    _tabCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabCtrl.indexIsChanging) return;
    _selectMode = false;
    _selected.clear();
    _loadAssets(_types[_tabCtrl.index]);
  }

  void _onScroll() {
    if (_loadingMore || !_hasMore) return;
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadAssets(RequestType type) async {
    setState(() {
      _loading = true; _assets = []; _groups = []; _permDenied = false;
      _hasMore = true; _page = 0; _album = null;
      _selectMode = false; _selected.clear();
    });

    final perm = await PhotoManager.requestPermissionExtend();
    if (perm != PermissionState.authorized) {
      await Permission.photos.request();
      await Permission.videos.request();
      final perm2 = await PhotoManager.requestPermissionExtend();
      if (perm2 != PermissionState.authorized) {
        if (mounted) setState(() { _permDenied = true; _loading = false; });
        return;
      }
    }

    _loadCounts();

    try {
      final albums = await PhotoManager.getAssetPathList(
        type: type, onlyAll: true, filterOption: _filterOption,
      );
      if (albums.isEmpty) {
        if (mounted) setState(() { _loading = false; _hasMore = false; });
        return;
      }
      _album = albums.first;
      final assets = await _album!.getAssetListPaged(page: 0, size: _pageSize);
      if (mounted) {
        setState(() {
          _assets = assets;
          _groups = _buildGroups(assets);
          _page = 1;
          _hasMore = assets.length == _pageSize;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _loadCounts() async {
    for (final type in _types) {
      try {
        final albums = await PhotoManager.getAssetPathList(
          type: type, onlyAll: true, filterOption: _filterOption,
        );
        if (albums.isNotEmpty) {
          final count = await albums.first.assetCountAsync;
          if (mounted) setState(() { _counts[type] = count; });
        }
      } catch (_) {}
    }
  }

  Future<void> _loadMore() async {
    if (_album == null || _loadingMore || !_hasMore) return;
    setState(() { _loadingMore = true; });
    try {
      final more = await _album!.getAssetListPaged(page: _page, size: _pageSize);
      if (mounted) {
        setState(() {
          _assets.addAll(more);
          _groups = _buildGroups(_assets);
          _page++;
          _hasMore = more.length == _pageSize;
          _loadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _loadingMore = false; });
    }
  }

  List<_DateGroup> _buildGroups(List<AssetEntity> assets) {
    final map = <String, List<AssetEntity>>{};
    final order = <String>[];
    for (final a in assets) {
      final label = _dateLabel(a.createDateTime);
      if (!map.containsKey(label)) {
        map[label] = [];
        order.add(label);
      }
      map[label]!.add(a);
    }
    return order.map((k) => _DateGroup(k, map[k]!)).toList();
  }

  String _dateLabel(DateTime dt) {
    final today = DateUtils.dateOnly(DateTime.now());
    final day = DateUtils.dateOnly(dt);
    if (day == today) return '오늘';
    if (day == today.subtract(const Duration(days: 1))) return '어제';
    return '${dt.year}년 ${dt.month}월 ${dt.day}일';
  }

  Future<void> _tapAsset(AssetEntity asset) async {
    if (_selectMode) {
      setState(() {
        if (_selected.contains(asset.id)) {
          _selected.remove(asset.id);
          if (_selected.isEmpty) _selectMode = false;
        } else {
          _selected.add(asset.id);
        }
      });
      return;
    }
    if (asset.type == AssetType.video) {
      // 갤러리 동영상은 content URI 반환 — 복사 없이 원본 참조
      final uri = await asset.getMediaUrl();
      if (uri == null || !mounted) return;
      Navigator.of(context).pop<({String path, bool isVideo})>(
        (path: uri, isVideo: true),
      );
      return;
    }
    final file = await asset.file;
    if (file == null || !mounted) return;
    Navigator.of(context).pop<({String path, bool isVideo})>(
      (path: file.path, isVideo: false),
    );
  }

  void _longPressAsset(AssetEntity asset) {
    setState(() {
      _selectMode = true;
      _selected.add(asset.id);
    });
  }

  Future<void> _deleteSelected() async {
    final count = _selected.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('삭제'),
        content: Text('선택한 $count개를 영구적으로 삭제합니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('삭제', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ids = _selected.toList();
    await PhotoManager.editor.deleteWithIds(ids);

    setState(() {
      _assets.removeWhere((a) => ids.contains(a.id));
      _groups = _buildGroups(_assets);
      _selected.clear();
      _selectMode = false;
    });
    _loadCounts();
  }

  String _tabLabel(int i) {
    const labels = ['전체', '사진', '동영상'];
    final count = _counts[_types[i]];
    return count != null ? '${labels[i]} ($count)' : labels[i];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _selectMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() { _selectMode = false; _selected.clear(); }),
              )
            : null,
        title: _selectMode ? Text('${_selected.length}개 선택됨') : const Text('갤러리'),
        actions: _selectMode
            ? [
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _selected.isNotEmpty ? _deleteSelected : null,
                ),
              ]
            : null,
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: List.generate(3, (i) => Tab(text: _tabLabel(i))),
        ),
      ),
      body: _permDenied
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline, size: 48,
                        color: Theme.of(context).colorScheme.error),
                    const SizedBox(height: 16),
                    const Text(
                      '사진/동영상 접근 권한이 필요합니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, height: 1.6),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => _loadAssets(_types[_tabCtrl.index]),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('권한 허용하기'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () async {
                        await openAppSettings();
                        if (mounted) _loadAssets(_types[_tabCtrl.index]);
                      },
                      child: const Text('설정에서 변경'),
                    ),
                  ],
                ),
              ),
            )
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _groups.isEmpty
                  ? const Center(child: Text('항목이 없습니다'))
                  : Scrollbar(
                      controller: _scrollCtrl,
                      thumbVisibility: true,
                      interactive: true,
                      child: CustomScrollView(
                        controller: _scrollCtrl,
                        slivers: [
                          for (final group in _groups) ...[
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                                child: Text(
                                  group.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                            SliverGrid(
                              delegate: SliverChildBuilderDelegate(
                                (ctx, i) => _AssetTile(
                                  asset: group.assets[i],
                                  selected: _selected.contains(group.assets[i].id),
                                  selectMode: _selectMode,
                                  onTap: () => _tapAsset(group.assets[i]),
                                  onLongPress: _selectMode
                                      ? null
                                      : () => _longPressAsset(group.assets[i]),
                                ),
                                childCount: group.assets.length,
                              ),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 2,
                                mainAxisSpacing: 2,
                              ),
                            ),
                          ],
                          if (_loadingMore)
                            const SliverToBoxAdapter(
                              child: Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
    );
  }
}

class _AssetTile extends StatelessWidget {
  final AssetEntity asset;
  final bool selected;
  final bool selectMode;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _AssetTile({
    required this.asset,
    required this.selected,
    required this.selectMode,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
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
          if (selected)
            const ColoredBox(color: Color(0x33000000)),
          if (selectMode)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : const Color(0x4D000000),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: selected
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}
