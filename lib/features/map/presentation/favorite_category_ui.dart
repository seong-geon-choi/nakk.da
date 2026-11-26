import 'package:flutter/material.dart';

import '../data/favorite_store.dart';

/// 즐겨찾기 데이터 변경 콜백(저장은 받는 쪽에서).
typedef FavoriteDataChanged = Future<void> Function(FavoriteData data);

/// 새 카테고리 이름 입력(즐겨찾기 추가·수정 창의 '+ 새 카테고리'). 취소면 null.
/// 이미 있는 이름은 막는다.
Future<String?> askCategoryName(
  BuildContext context, {
  required List<FavoriteCategory> existing,
}) async {
  final ctrl = TextEditingController();
  String? error;
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        void submit() {
          final v = FavoriteStore.clean(ctrl.text);
          if (v.isEmpty) {
            setLocal(() => error = '이름을 입력하세요');
            return;
          }
          if (existing.any((c) => c.name == v)) {
            setLocal(() => error = '이미 있는 카테고리입니다');
            return;
          }
          Navigator.pop(ctx, v);
        }

        return AlertDialog(
          title: const Text('새 카테고리'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: '예: 포인트, 선착장, 주차',
              border: const OutlineInputBorder(),
              errorText: error,
            ),
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('취소')),
            FilledButton(onPressed: submit, child: const Text('확인')),
          ],
        );
      },
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
  return result;
}

/// 카테고리 색 고르기(팔레트 8색). 취소면 null.
Future<int?> pickCategoryColor(BuildContext context, int current) =>
    showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('색 선택'),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final c in FavoriteStore.palette)
              GestureDetector(
                onTap: () => Navigator.pop(ctx, c),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(c),
                    border: c == current
                        ? Border.all(
                            color: Theme.of(ctx).colorScheme.onSurface,
                            width: 3)
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );

/// 지도 ⭐ 길게 누르기로 여는 즐겨찾기 시트.
/// - 체크박스: 지도 표시 켜고 끄기(맨 위 '전체'는 모두/없음 토글).
/// - 카테고리 이름 탭: 아래로 즐겨찾기 목록 펼치기/접기.
/// - 즐겨찾기 길게 누르기: 그 자리에서 이름·메모 입력 모드(저장해도 시트에 머무름). 📍: 지도에서 그 위치로.
/// - [편집] 또는 카테고리·즐겨찾기 길게 누르기: 편집 모드(카테고리 이름·색·순서·삭제·추가, 즐겨찾기 삭제).
class FavoriteBrowserSheet extends StatefulWidget {
  final FavoriteData Function() data;
  final Set<String> hidden;
  final ValueChanged<Set<String>> onHiddenChanged;
  final FavoriteDataChanged onDataChanged;
  final Future<void> Function(int index) onDeleteFavorite;
  final ValueChanged<int> onGoTo;

  const FavoriteBrowserSheet({
    super.key,
    required this.data,
    required this.hidden,
    required this.onHiddenChanged,
    required this.onDataChanged,
    required this.onDeleteFavorite,
    required this.onGoTo,
  });

  @override
  State<FavoriteBrowserSheet> createState() => _FavoriteBrowserSheetState();
}

class _FavoriteBrowserSheetState extends State<FavoriteBrowserSheet> {
  late Set<String> _hidden = {...widget.hidden};
  final Set<String> _expanded = {};
  bool _edit = false;
  int? _editing; // 입력 모드인 즐겨찾기(포인트 인덱스)
  final _nameCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();
  // 카테고리 이름 입력 모드(팝업 없이 그 자리에서): 이름 바꾸기 / 새로 추가.
  String? _renaming; // 이름 바꾸는 중인 카테고리
  bool _adding = false;
  final _catCtrl = TextEditingController();
  String? _catError;

  FavoriteData get _data => widget.data();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _memoCtrl.dispose();
    _catCtrl.dispose();
    super.dispose();
  }

  void _setHidden(Set<String> h) {
    setState(() => _hidden = h);
    widget.onHiddenChanged(h);
  }

  Future<void> _commit(FavoriteData d, [Map<String, String> renamed = const {}]) async {
    await widget.onDataChanged(d);
    if (renamed.isNotEmpty) {
      // 이름이 바뀐 카테고리는 숨김·펼침 상태도 새 이름으로.
      final h = _hidden.map((c) => renamed[c] ?? c).toSet();
      final e = _expanded.map((c) => renamed[c] ?? c).toSet();
      _expanded
        ..clear()
        ..addAll(e);
      _setHidden(h);
    }
    if (mounted) setState(() {});
  }

  /// 입력한 카테고리 이름 검사 — 문제가 있으면 오류 문구.
  String? _catNameError(String v, {String? self}) {
    if (v.isEmpty) return '이름을 입력하세요';
    if (v != self && _data.categories.any((c) => c.name == v)) {
      return '이미 있는 카테고리입니다';
    }
    return null;
  }

  void _closeCatInput() => setState(() {
        _renaming = null;
        _adding = false;
        _catError = null;
      });

  void _startAdd() {
    _catCtrl.text = '';
    setState(() {
      _adding = true;
      _renaming = null;
      _editing = null;
      _catError = null;
    });
  }

  Future<void> _submitAdd() async {
    final name = FavoriteStore.clean(_catCtrl.text);
    final err = _catNameError(name);
    if (err != null) {
      setState(() => _catError = err);
      return;
    }
    _closeCatInput();
    await _commit(_data.copyWith(categories: [
      ..._data.categories,
      FavoriteCategory(name, _data.nextColor()),
    ]));
  }

  void _startRename(FavoriteCategory c) {
    _catCtrl.text = c.name;
    setState(() {
      _renaming = c.name;
      _adding = false;
      _editing = null;
      _catError = null;
    });
  }

  Future<void> _submitRename() async {
    final old = _renaming;
    if (old == null) return;
    final name = FavoriteStore.clean(_catCtrl.text);
    final err = _catNameError(name, self: old);
    if (err != null) {
      setState(() => _catError = err);
      return;
    }
    _closeCatInput();
    if (name == old) return;
    final d = _data;
    final c = d.category(old);
    if (c == null) return;
    await _commit(
      d.copyWith(
        categories: [
          for (final x in d.categories) x.name == c.name ? x.copyWith(name: name) : x
        ],
        points: [
          for (final p in d.points)
            p.category == c.name ? p.copyWith(category: name) : p
        ],
      ),
      {c.name: name},
    );
  }

  Future<void> _recolor(FavoriteCategory c) async {
    final color = await pickCategoryColor(context, c.color);
    if (color == null) return;
    final d = _data;
    await _commit(d.copyWith(categories: [
      for (final x in d.categories) x.name == c.name ? x.copyWith(color: color) : x
    ]));
  }

  Future<void> _deleteCategory(FavoriteCategory c) async {
    final d = _data;
    final count = d.points.where((p) => p.category == c.name).length;
    String? how = 'move';
    if (count > 0) {
      how = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('\'${c.name}\' 삭제'),
          content: Text('이 카테고리의 즐겨찾기 $count개를 어떻게 할까요?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('취소')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'delete'),
                child: const Text('함께 삭제')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, 'move'),
                child: const Text('미지정으로 옮기기')),
          ],
        ),
      );
    }
    if (how == null) return;
    final cats = d.categories.where((x) => x.name != c.name).toList();
    if (how == 'move' &&
        count > 0 &&
        !cats.any((x) => x.name == FavoriteStore.defaultCategory)) {
      cats.add(FavoriteCategory(
          FavoriteStore.defaultCategory, FavoriteStore.palette.first));
    }
    await _commit(d.copyWith(
      categories: cats,
      points: how == 'delete'
          ? d.points.where((p) => p.category != c.name).toList()
          : [
              for (final p in d.points)
                p.category == c.name
                    ? p.copyWith(category: FavoriteStore.defaultCategory)
                    : p
            ],
    ));
  }

  void _reorder(int from, int to) {
    final cats = [..._data.categories];
    if (to > from) to--;
    cats.insert(to, cats.removeAt(from));
    _commit(_data.copyWith(categories: cats)); // '미지정'은 저장 시 맨 아래로
  }

  /// 즐겨찾기를 그 자리에서 입력 모드로.
  void _startInline(int i) {
    final f = _data.points[i];
    _nameCtrl.text = f.name;
    _memoCtrl.text = f.memo;
    setState(() {
      _editing = i;
      _renaming = null;
      _adding = false;
    });
  }

  /// 입력 내용 저장 후 목록으로(시트는 그대로).
  Future<void> _saveInline() async {
    final i = _editing;
    if (i == null) return;
    final d = _data;
    if (i >= d.points.length) {
      setState(() => _editing = null);
      return;
    }
    final f = d.points[i];
    final name = FavoriteStore.clean(_nameCtrl.text);
    final points = [...d.points];
    points[i] = f.copyWith(
        name: name.isEmpty ? f.name : name,
        memo: FavoriteStore.clean(_memoCtrl.text));
    setState(() => _editing = null);
    await _commit(d.copyWith(points: points));
  }

  Future<void> _deleteFavorite(int i) async {
    setState(() => _editing = null);
    await widget.onDeleteFavorite(i);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final cs = Theme.of(context).colorScheme;
    final names = d.categories.map((c) => c.name).toSet();
    final visibleCount = names.where((n) => !_hidden.contains(n)).length;
    final allValue = visibleCount == names.length
        ? true
        : (visibleCount == 0 ? false : null);

    // 입력 중 키보드에 가리지 않게 아래 여백.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 제목줄(편집 모드면 '완료').
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(children: [
                const Icon(Icons.star, color: Color(0xFFFFB300)),
                const SizedBox(width: 8),
                Text(_edit ? '즐겨찾기 편집' : '즐겨찾기',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                const Spacer(),
                // 편집 ↔ 완료(길게 누르기로도 편집 모드 진입).
                if (_edit)
                  TextButton(
                      onPressed: () => setState(() {
                            _edit = false;
                            _editing = null;
                            _renaming = null;
                            _adding = false;
                            _catError = null;
                          }),
                      child: const Text('완료'))
                else
                  TextButton.icon(
                      onPressed: () => setState(() => _edit = true),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('편집')),
              ]),
            ),
            if (_edit)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  '색 원: 색 바꾸기 · 이름: 이름 바꾸기 · ≡ 끌어 순서 바꾸기',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ),
            // 맨 위 '전체' 토글(모두 ↔ 없음).
            Row(children: [
              Checkbox(
                tristate: true,
                value: allValue,
                onChanged: (_) =>
                    _setHidden(allValue == true ? {...names} : <String>{}),
              ),
              Text('전체 (${d.points.length})',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
            const Divider(height: 1),
            Flexible(
              child: ReorderableListView(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                onReorder: _reorder,
                children: [
                  for (var ci = 0; ci < d.categories.length; ci++)
                    _categoryBlock(d, d.categories[ci], ci, cs),
                ],
              ),
            ),
            if (_edit && _adding)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 4, 8),
                child: Row(children: [
                  Expanded(child: _catField(_submitAdd, hint: '새 카테고리 이름')),
                  IconButton(
                      icon: const Icon(Icons.check),
                      tooltip: '추가',
                      onPressed: _submitAdd),
                  IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: '취소',
                      onPressed: _closeCatInput),
                ]),
              )
            else if (_edit)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _startAdd,
                  icon: const Icon(Icons.add),
                  label: const Text('카테고리 추가'),
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _categoryBlock(
      FavoriteData d, FavoriteCategory c, int ci, ColorScheme cs) {
    final isDefault = c.name == FavoriteStore.defaultCategory;
    final open = _expanded.contains(c.name);
    final items = <int>[
      for (var i = 0; i < d.points.length; i++)
        if (d.points[i].category == c.name) i
    ];
    return Column(
      key: ValueKey('cat-${c.name}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          // 체크박스만 표시 켜고 끄기.
          Checkbox(
            value: !_hidden.contains(c.name),
            onChanged: (v) {
              final h = {..._hidden};
              v == true ? h.remove(c.name) : h.add(c.name);
              _setHidden(h);
            },
          ),
          GestureDetector(
            onTap: _edit ? () => _recolor(c) : null,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: CircleAvatar(
                  radius: _edit ? 11 : 7, backgroundColor: Color(c.color)),
            ),
          ),
          // 이름 바꾸는 중: 그 자리에서 입력(✓ 저장, ✕ 취소).
          if (_renaming == c.name) ...[
            Expanded(child: _catField(_submitRename)),
            IconButton(
                icon: const Icon(Icons.check),
                tooltip: '저장',
                onPressed: _submitRename),
            IconButton(
                icon: const Icon(Icons.close),
                tooltip: '취소',
                onPressed: _closeCatInput),
          ] else ...[
          // 이름 탭: 펼치기(편집 모드에선 그 자리에서 이름 바꾸기). 길게: 편집 모드.
          Expanded(
            child: InkWell(
              onTap: _edit && !isDefault
                  ? () => _startRename(c)
                  : () => setState(() =>
                      open ? _expanded.remove(c.name) : _expanded.add(c.name)),
              // 길게: 편집 모드 + 바로 이름 입력(즐겨찾기와 같은 방식, '미지정'은 이름 고정).
              onLongPress: _edit
                  ? null
                  : () {
                      setState(() => _edit = true);
                      if (!isDefault) _startRename(c);
                    },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                child: Row(children: [
                  Flexible(
                    child: Text(c.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Text('  ${items.length}',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                ]),
              ),
            ),
          ),
          if (_edit) ...[
            if (!isDefault)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: '카테고리 삭제',
                onPressed: () => _deleteCategory(c),
              ),
            if (!isDefault)
            ReorderableDragStartListener(
              index: ci,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.drag_handle),
              ),
            ),
          ] else
            IconButton(
              icon: Icon(open ? Icons.expand_less : Icons.expand_more),
              onPressed: () => setState(() =>
                  open ? _expanded.remove(c.name) : _expanded.add(c.name)),
            ),
          ],
        ]),
        if (open)
          for (final i in items) _favoriteRow(d.points[i], i, cs),
        if (open && items.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('즐겨찾기가 없습니다',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ),
          ),
      ],
    );
  }

  /// 카테고리 이름 입력칸(이름 바꾸기·추가 공용). 엔터 = 저장.
  Widget _catField(VoidCallback onSubmit, {String? hint}) => TextField(
        controller: _catCtrl,
        autofocus: true,
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          errorText: _catError,
        ),
        onChanged: (_) {
          if (_catError != null) setState(() => _catError = null);
        },
        onSubmitted: (_) => onSubmit(),
      );

  Widget _favoriteRow(FavoritePoint f, int i, ColorScheme cs) {
    // 입력 모드: 이름·메모를 그 자리에서 고치고 저장(시트에 머무름).
    if (_editing == i) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(56, 4, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                  isDense: true, labelText: '이름'),
              textInputAction: TextInputAction.next,
            ),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: TextField(
                controller: _memoCtrl,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                    isDense: true, labelText: '메모'),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: () => setState(() => _editing = null),
                    child: const Text('취소')),
                FilledButton(
                    onPressed: _saveInline, child: const Text('저장')),
              ],
            ),
          ],
        ),
      );
    }
    return InkWell(
      // 길게: 편집 모드 + 입력 모드. 탭은 편집 모드에서만 입력 모드(평소엔 📍로 지도 이동).
      onTap: _edit ? () => _startInline(i) : null,
      onLongPress: _edit
          ? null
          : () {
              setState(() => _edit = true);
              _startInline(i);
            },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(56, 6, 0, 6),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.name, overflow: TextOverflow.ellipsis),
                // 제목 아래 내용은 살짝 들여쓰기.
                if (f.memo.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, top: 2),
                    child: Text(f.memo,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant)),
                  ),
              ],
            ),
          ),
          if (_edit)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: '삭제',
              onPressed: () => _deleteFavorite(i),
            ),
          IconButton(
            icon: Icon(Icons.place_outlined, color: cs.primary),
            tooltip: '지도에서 보기',
            onPressed: () => widget.onGoTo(i),
          ),
        ]),
      ),
    );
  }
}
