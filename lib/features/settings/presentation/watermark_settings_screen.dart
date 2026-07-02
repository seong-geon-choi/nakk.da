import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'settings_provider.dart';

/// 헤비(번들) 폰트 패밀리명 — watermark.dart kWatermarkHeavyFont 및 pubspec과 일치.
const String _kHeavyFont = 'BlackHanSans';

class WatermarkSettingsScreen extends ConsumerStatefulWidget {
  const WatermarkSettingsScreen({super.key});

  @override
  ConsumerState<WatermarkSettingsScreen> createState() =>
      _WatermarkSettingsScreenState();
}

class _WatermarkSettingsScreenState
    extends ConsumerState<WatermarkSettingsScreen> {
  final Map<WatermarkLineType, TextEditingController> _customCtrls = {};
  bool _darkPreview = false;
  WatermarkLineType? _selectedType; // 미리보기에서 선택된 박스
  final _scrollController = ScrollController();
  final Map<WatermarkLineType, GlobalKey> _cardKeys = {
    for (final t in WatermarkLineType.values) t: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    final wm = ref.read(settingsProvider).valueOrNull?.watermark;
    for (final b in wm?.boxes ?? const <WatermarkBox>[]) {
      if (_isCustom(b.type)) {
        _customCtrls[b.type] = TextEditingController(text: b.customText);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _customCtrls.values) {
      c.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _update(WatermarkSettings updated) =>
      ref.read(settingsProvider.notifier).updateWatermark(updated);

  WatermarkSettings _updateBox(WatermarkSettings wm, WatermarkLineType type,
      WatermarkBox Function(WatermarkBox) f) {
    final boxes = wm.boxes.map((b) => b.type == type ? f(b) : b).toList();
    return wm.copyWith(boxes: boxes);
  }

  void _moveBox(
          WatermarkSettings wm, WatermarkLineType type, double dx, double dy) =>
      _update(_updateBox(wm, type, (b) => b.copyWith(dx: dx, dy: dy)));

  /// 컬러피커로 고른 색을 박스에 적용 + 사용자 색상 히스토리(최신순, 중복/프리셋 제외)에 저장
  void _pickCustomColor(
      WatermarkSettings wm, WatermarkLineType type, int color) {
    final isPreset = WatermarkSettings.textPresets.contains(color);
    final history = isPreset
        ? wm.customColors
        : [
            color,
            ...wm.customColors.where((c) => c != color),
          ].take(WatermarkSettings.maxCustomColors).toList();
    final boxes = wm.boxes
        .map((b) => b.type == type ? b.copyWith(textColor: color) : b)
        .toList();
    _update(wm.copyWith(boxes: boxes, customColors: history));
  }

  /// 미리보기에서 박스 선택 → 해당 설정 카드를 펼치고 그 위치로 스크롤
  void _selectBox(WatermarkLineType type) {
    setState(() => _selectedType = type);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _cardKeys[type]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 300), alignment: 0.05);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final wm = ref.watch(settingsProvider).valueOrNull?.watermark ??
        WatermarkSettings();
    final activeIndex =
        ref.watch(settingsProvider).valueOrNull?.watermarkTemplateIndex ?? 0;

    // 템플릿 전환 시 커스텀 텍스트 컨트롤러를 새 템플릿 값으로 동기화
    ref.listen(
      settingsProvider.select((s) => s.valueOrNull?.watermarkTemplateIndex),
      (_, _) {
        final newWm = ref.read(settingsProvider).valueOrNull?.watermark;
        if (newWm == null) return;
        for (final b in newWm.boxes) {
          if (_isCustom(b.type)) {
            final c = _customCtrls[b.type] ??=
                TextEditingController();
            if (c.text != b.customText) c.text = b.customText;
          }
        }
        setState(() => _selectedType = null);
      },
    );

    // 키보드가 올라오면 상단 미리보기/탭을 숨겨 입력창 공간을 확보(오버플로 방지)
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      appBar: AppBar(title: const Text('워터마크 설정')),
      body: Column(
        children: [
          if (!keyboardOpen) ...[
            _TemplateTabs(
              active: activeIndex,
              onSelect: (i) =>
                  ref.read(settingsProvider.notifier).selectWatermarkTemplate(i),
            ),
            const Divider(height: 1),
            _PreviewSection(
              wm: wm,
              dark: _darkPreview,
              selectedType: _selectedType,
              onToggleBg: (v) => setState(() => _darkPreview = v),
              onMoveBox: (type, x, y) => _moveBox(wm, type, x, y),
              onSelectBox: _selectBox,
            ),
            const Divider(height: 1),
          ],
          Expanded(
            child: ListView(
              controller: _scrollController,
              children: [
                // ── 컨테이너 배경 ──
                _Header('배경 (전체 박스를 감싸는 컨테이너)'),
                _BgPalette(
                  index: wm.bgColorIndex,
                  onSelect: (i) => _update(wm.copyWith(bgColorIndex: i)),
                ),
                ListTile(
                  leading: const Icon(Icons.opacity),
                  title: const Text('배경 투명도'),
                  trailing: Text('${(wm.bgOpacity * 100).round()}%',
                      style: const TextStyle(fontSize: 13)),
                  subtitle: Slider(
                    value: wm.bgOpacity,
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    label: '${(wm.bgOpacity * 100).round()}%',
                    onChanged: (v) => _update(wm.copyWith(bgOpacity: v)),
                  ),
                ),
                CheckboxListTile(
                  secondary: const Icon(Icons.border_outer),
                  title: const Text('컨테이너 테두리 감추기'),
                  subtitle: const Text('카메라 화면의 드래그 안내 테두리를 숨깁니다 (저장 사진엔 원래 표시되지 않음)'),
                  value: wm.hideContainerBorder,
                  onChanged: (v) =>
                      _update(wm.copyWith(hideContainerBorder: v ?? false)),
                ),
                const Divider(height: 1),

                // ── 박스별 설정 ──
                _Header('박스별 설정  (미리보기에서 박스를 탭하면 여기로 이동)'),
                for (final box in wm.boxes)
                  _BoxCard(
                    key: _cardKeys[box.type],
                    box: box,
                    expanded: _selectedType == box.type,
                    customCtrl: _isCustom(box.type)
                        ? _customCtrls[box.type]
                        : null,
                    customColors: wm.customColors,
                    onToggle: () => setState(() => _selectedType =
                        _selectedType == box.type ? null : box.type),
                    onUpdate: (f) => _update(_updateBox(wm, box.type, f)),
                    onPickColor: (c) => _pickCustomColor(wm, box.type, c),
                  ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 공통 텍스트/포맷 헬퍼 ─────────────────────────────────────

String _fontFamily(WatermarkFont f) => switch (f) {
      WatermarkFont.monospace => 'monospace',
      WatermarkFont.serif => 'serif',
      WatermarkFont.sansSerif => 'sans-serif',
      WatermarkFont.heavy => _kHeavyFont,
    };

FontWeight _fontWeight(WatermarkWeight w) => switch (w) {
      WatermarkWeight.normal => FontWeight.w400,
      WatermarkWeight.bold => FontWeight.w700,
      WatermarkWeight.black => FontWeight.w900,
    };

TextAlign _textAlign(WatermarkAlign a) => switch (a) {
      WatermarkAlign.left => TextAlign.left,
      WatermarkAlign.center => TextAlign.center,
      WatermarkAlign.right => TextAlign.right,
    };

String _formatDate(DateTime dt, String format) {
  final y = dt.year.toString();
  final yy = (dt.year % 100).toString().padLeft(2, '0');
  final mm = dt.month.toString().padLeft(2, '0');
  final dd = dt.day.toString().padLeft(2, '0');
  final hh = dt.hour.toString().padLeft(2, '0');
  final min = dt.minute.toString().padLeft(2, '0');
  final sec = dt.second.toString().padLeft(2, '0');
  final mmm = _monthAbbr[dt.month - 1];
  switch (format) {
    case 'yy/MM/dd':
      return '$yy/$mm/$dd';
    case 'MM/dd':
      return '$mm/$dd';
    case 'MMM/dd':
      return '$mmm/$dd';
    case 'yyyy MMM dd':
      return '$y $mmm $dd';
    case 'yyyy-MM-dd HH:mm:ss':
      return '$y-$mm-$dd $hh:$min:$sec';
    case 'yyyy-MM-dd HH:mm':
      return '$y-$mm-$dd $hh:$min';
    default:
      return '$y-$mm-$dd';
  }
}

const _monthAbbr = [
  'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
  'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
];

String _formatTime(DateTime dt, String format) {
  final hh = dt.hour.toString().padLeft(2, '0');
  final min = dt.minute.toString().padLeft(2, '0');
  final sec = dt.second.toString().padLeft(2, '0');
  return format == 'HH:mm:ss' ? '$hh:$min:$sec' : '$hh:$min';
}

/// 미리보기용 박스 텍스트(빈 커스텀은 플레이스홀더)
String _previewBoxText(WatermarkBox b, DateTime now) {
  switch (b.type) {
    case WatermarkLineType.date:
      return _formatDate(now, b.dateFormat);
    case WatermarkLineType.time:
      return b.timeFormat.isEmpty ? '' : _formatTime(now, b.timeFormat);
    case WatermarkLineType.customText:
    case WatermarkLineType.customText2:
      final placeholder =
          b.type == WatermarkLineType.customText ? '(텍스트1)' : '(텍스트2)';
      return switch (b.textContent) {
        WatermarkTextContent.year => '${now.year}',
        WatermarkTextContent.address => '📍 시/군/구/동',
        WatermarkTextContent.text =>
          b.customText.trim().isEmpty ? placeholder : b.customText.trim(),
      };
  }
}

String _boxLabel(WatermarkLineType t) => switch (t) {
      WatermarkLineType.date => '📅 날짜',
      WatermarkLineType.time => '🕐 시간',
      WatermarkLineType.customText => '📝 텍스트1',
      WatermarkLineType.customText2 => '📝 텍스트2',
    };

bool _isCustom(WatermarkLineType t) =>
    t == WatermarkLineType.customText || t == WatermarkLineType.customText2;

// ── 템플릿 탭 (3슬롯) ─────────────────────────────────────────

class _TemplateTabs extends StatelessWidget {
  final int active;
  final void Function(int) onSelect;
  const _TemplateTabs({required this.active, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          for (var i = 0; i < 3; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
                child: GestureDetector(
                  onTap: () => onSelect(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == active
                          ? cs.primaryContainer
                          : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: i == active
                              ? cs.primary
                              : cs.outline.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      '템플릿 ${i + 1}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            i == active ? FontWeight.w700 : FontWeight.w400,
                        color: i == active
                            ? cs.primary
                            : cs.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── 미리보기 섹션 ─────────────────────────────────────────────

class _PreviewSection extends StatelessWidget {
  final WatermarkSettings wm;
  final bool dark;
  final WatermarkLineType? selectedType;
  final void Function(bool) onToggleBg;
  final void Function(WatermarkLineType, double, double) onMoveBox;
  final void Function(WatermarkLineType) onSelectBox;

  const _PreviewSection({
    required this.wm,
    required this.dark,
    required this.selectedType,
    required this.onToggleBg,
    required this.onMoveBox,
    required this.onSelectBox,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('미리보기',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.primary)),
              const Spacer(),
              _BgToggle(dark: dark, onChanged: onToggleBg),
            ],
          ),
          const SizedBox(height: 8),
          _WatermarkPreview(
            wm: wm,
            dark: dark,
            selectedType: selectedType,
            onMoveBox: onMoveBox,
            onSelectBox: onSelectBox,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.touch_app_outlined, size: 15, color: cs.primary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '박스를 드래그해 정렬하세요(서로 겹치지 않게 정렬됩니다). 박스를 탭하면 아래 설정으로 이동합니다. 전체 위치는 카메라 화면에서 옮깁니다.',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BgToggle extends StatelessWidget {
  final bool dark;
  final void Function(bool) onChanged;
  const _BgToggle({required this.dark, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Chip(
          label: '밝은 배경',
          icon: Icons.light_mode,
          selected: !dark,
          onTap: () => onChanged(false),
        ),
        const SizedBox(width: 6),
        _Chip(
          label: '어두운 배경',
          icon: Icons.dark_mode,
          selected: dark,
          onTap: () => onChanged(true),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _Chip(
      {required this.label,
      required this.icon,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? cs.primary : cs.outline.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color:
                    selected ? cs.primary : cs.onSurface.withValues(alpha: 0.6)),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: selected
                        ? cs.primary
                        : cs.onSurface.withValues(alpha: 0.6),
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}

// ── 레이아웃 계산 결과 ────────────────────────────────────────

class _BoxLayout {
  final WatermarkLineType type;
  final Rect rect;
  _BoxLayout(this.type, this.rect);
}

class _Layout {
  final List<_BoxLayout> boxes;
  final Offset containerOffset;
  final Size containerSize;
  final double pad;
  final double shortSidePx;
  final Offset groupMin;
  final double canvasH;
  _Layout(this.boxes, this.containerOffset, this.containerSize, this.pad,
      this.shortSidePx, this.groupMin, this.canvasH);
  bool get isEmpty => boxes.isEmpty;
}

// ── 워터마크 미리보기 ──────────────────────────────────────────

class _WatermarkPreview extends StatefulWidget {
  final WatermarkSettings wm;
  final bool dark;
  final WatermarkLineType? selectedType;
  final void Function(WatermarkLineType, double, double) onMoveBox;
  final void Function(WatermarkLineType) onSelectBox;

  const _WatermarkPreview({
    required this.wm,
    required this.dark,
    required this.selectedType,
    required this.onMoveBox,
    required this.onSelectBox,
  });

  @override
  State<_WatermarkPreview> createState() => _WatermarkPreviewState();
}

class _WatermarkPreviewState extends State<_WatermarkPreview> {
  final _areaKey = GlobalKey();

  // 드래그 상태 (드래그 시작 시점 레이아웃을 동결해 1:1 추종 + 컨테이너 점프 방지)
  WatermarkLineType? _dragType;
  _Layout? _frozen;
  Offset _grab = Offset.zero;
  Offset? _liveTopLeft;

  _Layout _computeLayout(double canvasW, WatermarkSettings wm, DateTime now) {
    // 카메라와 동일한 스케일: shortSidePx = 캔버스 너비(≈화면 너비).
    final shortSidePx = canvasW;
    final visible = wm.boxes
        .where((b) => b.visible && _previewBoxText(b, now).isNotEmpty)
        .toList();
    if (visible.isEmpty) {
      return _Layout(
          [], Offset.zero, Size.zero, 0, shortSidePx, Offset.zero, 140);
    }

    final sizes = <Size>[];
    final positions = <Offset>[];
    double maxFont = 0;
    for (final b in visible) {
      final scaledFont = b.fontSize * shortSidePx / 480.0;
      maxFont = maxFont > scaledFont ? maxFont : scaledFont;
      final tp = TextPainter(
        text: TextSpan(
          text: _previewBoxText(b, now),
          style: TextStyle(
            fontSize: scaledFont,
            fontWeight: _fontWeight(b.weight),
            fontFamily: _fontFamily(b.fontFamily),
            height: 1.25,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: _textAlign(b.alignment),
        textScaler: TextScaler.noScaling,
      )..layout();
      // +2px: 시스템 글꼴 배율 무시(noScaling)와 함께 서브픽셀 줄바꿈 방지
      final nat = Size(tp.width + 2, tp.height);
      // 90°/270° 회전 시 footprint 가로·세로가 뒤바뀜
      sizes.add(b.quarterTurns % 2 != 0 ? Size(nat.height, nat.width) : nat);
      positions.add(Offset(b.dx * shortSidePx, b.dy * shortSidePx));
    }

    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (var i = 0; i < visible.length; i++) {
      final p = positions[i], s = sizes[i];
      minX = minX < p.dx ? minX : p.dx;
      minY = minY < p.dy ? minY : p.dy;
      maxX = maxX > p.dx + s.width ? maxX : p.dx + s.width;
      maxY = maxY > p.dy + s.height ? maxY : p.dy + s.height;
    }

    final pad = maxFont * 0.4;
    final containerSize =
        Size((maxX - minX) + pad * 2, (maxY - minY) + pad * 2);
    // 캔버스는 컨테이너가 보일 정도만(세로로 길지 않게) — 약간의 여백만 둠
    const vpad = 40.0;
    final canvasH = math.max(containerSize.height + vpad * 2, 140.0);
    // 컨테이너를 캔버스 중앙에 배치(박스 상대 배치/스타일 편집용).
    // 컨테이너의 실제 위치는 카메라에서만 지정·기억한다.
    final containerOffset = Offset(
      ((canvasW - containerSize.width) / 2).clamp(0.0, double.infinity),
      ((canvasH - containerSize.height) / 2).clamp(0.0, double.infinity),
    );

    final boxes = <_BoxLayout>[];
    for (var i = 0; i < visible.length; i++) {
      final p = positions[i], s = sizes[i];
      boxes.add(_BoxLayout(
        visible[i].type,
        Rect.fromLTWH(
          containerOffset.dx + pad + (p.dx - minX),
          containerOffset.dy + pad + (p.dy - minY),
          s.width,
          s.height,
        ),
      ));
    }

    return _Layout(boxes, containerOffset, containerSize, pad, shortSidePx,
        Offset(minX, minY), canvasH);
  }

  Offset? _areaLocal(Offset global) {
    final rb = _areaKey.currentContext?.findRenderObject() as RenderBox?;
    return rb?.globalToLocal(global);
  }

  /// 드래그 박스가 다른 박스와 겹치면 침투가 적은 축으로 밀어내 겹침 방지
  Offset _resolveCollisions(Offset tl, Size size, _Layout frozen) {
    var pos = tl;
    for (var iter = 0; iter < 4; iter++) {
      var moved = false;
      final dr = pos & size;
      for (final o in frozen.boxes) {
        if (o.type == _dragType) continue;
        final r = o.rect;
        if (!dr.overlaps(r)) continue;
        final pushLeft = dr.right - r.left; // 왼쪽으로 빼기(음수)
        final pushRight = r.right - dr.left; // 오른쪽으로 빼기(양수)
        final pushUp = dr.bottom - r.top; // 위로 빼기(음수)
        final pushDown = r.bottom - dr.top; // 아래로 빼기(양수)
        final dx = pushLeft < pushRight ? -pushLeft : pushRight;
        final dy = pushUp < pushDown ? -pushUp : pushDown;
        if (dx.abs() < dy.abs()) {
          pos = Offset(pos.dx + dx, pos.dy);
        } else {
          pos = Offset(pos.dx, pos.dy + dy);
        }
        moved = true;
      }
      if (!moved) break;
    }
    return pos;
  }

  @override
  Widget build(BuildContext context) {
    final wm = widget.wm;
    final dark = widget.dark;
    final now = DateTime.now();

    final bgColor = dark ? const Color(0xFF22232B) : const Color(0xFFE8EAF0);
    final dashBase = dark ? Colors.white70 : Colors.black54;
    final containerColor = Color(wm.bgColorArgb);

    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasW = constraints.maxWidth;
        final layout = (_dragType != null && _frozen != null)
            ? _frozen!
            : _computeLayout(canvasW, wm, now);
        final canvasH = layout.canvasH;

        final children = <Widget>[
          Container(color: bgColor),
        ];

        if (!layout.isEmpty) {
          // 컨테이너 배경
          children.add(Positioned(
            left: layout.containerOffset.dx,
            top: layout.containerOffset.dy,
            child: Container(
              width: layout.containerSize.width,
              height: layout.containerSize.height,
              decoration: BoxDecoration(
                color: containerColor,
                borderRadius: BorderRadius.circular(layout.pad * 0.5),
              ),
            ),
          ));

          // 각 박스 (항상 점선 테두리, 선택/드래그 시 강조)
          for (final bl in layout.boxes) {
            final box = wm.boxes.firstWhere((b) => b.type == bl.type);
            final dragging = _dragType == bl.type;
            final selected = widget.selectedType == bl.type;
            final tl = (dragging && _liveTopLeft != null)
                ? _liveTopLeft!
                : bl.rect.topLeft;
            final highlight = dragging || selected;
            final dashColor = highlight ? Colors.amber : dashBase;

            final turns = box.quarterTurns;
            final swapped = turns % 2 != 0;
            // footprint(bl.rect)에서 회전 전 파라그래프 자연 크기 복원
            final natW = swapped ? bl.rect.height : bl.rect.width;
            final natH = swapped ? bl.rect.width : bl.rect.height;
            final textWidget = SizedBox(
              width: natW,
              height: natH,
              child: Text(
                _previewBoxText(box, now),
                textAlign: _textAlign(box.alignment),
                textScaler: TextScaler.noScaling,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  color: Color(box.textColor),
                  fontSize: box.fontSize * layout.shortSidePx / 480.0,
                  fontWeight: _fontWeight(box.weight),
                  fontFamily: _fontFamily(box.fontFamily),
                  height: 1.25,
                ),
              ),
            );
            final boxWidget = CustomPaint(
              foregroundPainter: _DashedBorderPainter(
                  color: dashColor, strokeWidth: highlight ? 2 : 1),
              child: turns % 4 == 0
                  ? textWidget
                  : RotatedBox(quarterTurns: turns, child: textWidget),
            );

            children.add(Positioned(
              left: tl.dx,
              top: tl.dy,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onSelectBox(bl.type),
                onPanStart: (d) {
                  final local = _areaLocal(d.globalPosition);
                  if (local == null) return;
                  setState(() {
                    _dragType = bl.type;
                    _frozen = layout;
                    _grab = bl.rect.topLeft - local;
                    _liveTopLeft = bl.rect.topLeft;
                  });
                },
                onPanUpdate: (d) {
                  final local = _areaLocal(d.globalPosition);
                  if (local == null || _frozen == null) return;
                  var newTL = local + _grab;
                  newTL = _resolveCollisions(newTL, bl.rect.size, _frozen!);
                  setState(() => _liveTopLeft = newTL);
                },
                onPanEnd: (_) => _commitDrag(),
                onPanCancel: _commitDrag,
                child: boxWidget,
              ),
            ));
          }
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            key: _areaKey,
            width: canvasW,
            height: canvasH,
            child: Stack(children: children),
          ),
        );
      },
    );
  }

  void _commitDrag() {
    final f = _frozen;
    final tl = _liveTopLeft;
    final type = _dragType;
    if (f != null && tl != null && type != null) {
      // 화면 좌상단 → dx/dy(shortSide 비율) 역변환 (동결 프레임 기준)
      final lx = tl.dx - f.containerOffset.dx - f.pad + f.groupMin.dx;
      final ly = tl.dy - f.containerOffset.dy - f.pad + f.groupMin.dy;
      widget.onMoveBox(type, lx / f.shortSidePx, ly / f.shortSidePx);
    }
    setState(() {
      _dragType = null;
      _frozen = null;
      _liveTopLeft = null;
    });
  }
}

// ── 점선 테두리 페인터 (박스 표시용) ───────────────────────────

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  const _DashedBorderPainter({required this.color, this.strokeWidth = 1.0});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    // 텍스트보다 살짝 바깥에 그려 글자와 겹치지 않게
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(-3, -2, size.width + 6, size.height + 4),
      const Radius.circular(4),
    );
    final path = Path()..addRRect(rrect);
    const dash = 4.0, gap = 3.0;
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final len = math.min(dash, metric.length - dist);
        canvas.drawPath(metric.extractPath(dist, dist + len), paint);
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}

// ── 배경 프리셋 팔레트 ─────────────────────────────────────────

class _BgPalette extends StatelessWidget {
  final int index;
  final void Function(int) onSelect;
  const _BgPalette({required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (var i = 0; i < WatermarkSettings.bgPresets.length; i++)
            _Swatch(
              color: Color(WatermarkSettings.bgPresets[i]),
              selected: i == index,
              onTap: () => onSelect(i),
            ),
        ],
      ),
    );
  }
}

// ── 박스별 설정 카드 ──────────────────────────────────────────

class _BoxCard extends StatelessWidget {
  final WatermarkBox box;
  final bool expanded;
  final VoidCallback onToggle;
  final TextEditingController? customCtrl;
  final List<int> customColors;
  final void Function(WatermarkBox Function(WatermarkBox)) onUpdate;
  final void Function(int color) onPickColor;

  const _BoxCard({
    super.key,
    required this.box,
    required this.expanded,
    required this.onToggle,
    required this.customCtrl,
    required this.customColors,
    required this.onUpdate,
    required this.onPickColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: expanded
            ? BorderSide(color: cs.primary, width: 1.5)
            : BorderSide.none,
      ),
      child: Column(
        children: [
          // 헤더 (탭하면 펼침/접힘)
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Row(
                children: [
                  Icon(expanded ? Icons.expand_less : Icons.expand_more,
                      size: 22),
                  const SizedBox(width: 4),
                  Text(_boxLabel(box.type),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (box.type == WatermarkLineType.date)
                    _FormatDropdown(
                      value: box.dateFormat,
                      options: const [
                        'yyyy-MM-dd',
                        'yy/MM/dd',
                        'MM/dd',
                        'MMM/dd',
                        'yyyy MMM dd',
                        'yyyy-MM-dd HH:mm:ss',
                        'yyyy-MM-dd HH:mm',
                      ],
                      labels: const [
                        '연-월-일',
                        '연(2)/월/일',
                        '월/일',
                        '영문월/일',
                        '연 영문월 일',
                        '연-월-일 시:분:초',
                        '연-월-일 시:분',
                      ],
                      onChanged: (v) =>
                          onUpdate((b) => b.copyWith(dateFormat: v)),
                    )
                  else if (box.type == WatermarkLineType.time)
                    _FormatDropdown(
                      value: box.timeFormat,
                      options: const ['HH:mm', 'HH:mm:ss', ''],
                      labels: const ['HH:mm', 'HH:mm:ss', '없음'],
                      onChanged: (v) =>
                          onUpdate((b) => b.copyWith(timeFormat: v)),
                    ),
                  const SizedBox(width: 8),
                  Switch(
                    value: box.visible,
                    onChanged: (v) => onUpdate((b) => b.copyWith(visible: v)),
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                children: [
          if (customCtrl != null) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Text('내용', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SegmentedButton<WatermarkTextContent>(
                      segments: const [
                        ButtonSegment(
                            value: WatermarkTextContent.text,
                            label: Text('텍스트')),
                        ButtonSegment(
                            value: WatermarkTextContent.year,
                            label: Text('연도')),
                        ButtonSegment(
                            value: WatermarkTextContent.address,
                            label: Text('주소')),
                      ],
                      selected: {box.textContent},
                      onSelectionChanged: (s) =>
                          onUpdate((b) => b.copyWith(textContent: s.first)),
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (box.textContent == WatermarkTextContent.text)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: customCtrl,
                  decoration: const InputDecoration(
                    hintText: '커스텀 텍스트 입력',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontSize: 14),
                  onChanged: (text) =>
                      onUpdate((b) => b.copyWith(customText: text)),
                ),
              ),
            if (box.textContent == WatermarkTextContent.address)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '📍 촬영 위치의 시/군/구/동 주소가 표시됩니다(온라인 필요, 없으면 생략).',
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.55)),
                ),
              ),
          ],
          // 글자 크기
          Row(
            children: [
              const Icon(Icons.format_size, size: 20),
              const SizedBox(width: 8),
              const Text('크기', style: TextStyle(fontSize: 13)),
              Expanded(
                child: Slider(
                  value: box.fontSize,
                  min: 16,
                  max: 80,
                  divisions: 16,
                  label: box.fontSize.toInt().toString(),
                  onChanged: (v) => onUpdate((b) => b.copyWith(fontSize: v)),
                ),
              ),
              Text('${box.fontSize.toInt()}',
                  style: const TextStyle(fontSize: 13)),
            ],
          ),
          // 굵기
          Row(
            children: [
              const Icon(Icons.format_bold, size: 20),
              const SizedBox(width: 8),
              const Text('굵기', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 12),
              Expanded(
                child: SegmentedButton<WatermarkWeight>(
                  segments: const [
                    ButtonSegment(
                        value: WatermarkWeight.normal, label: Text('보통')),
                    ButtonSegment(
                        value: WatermarkWeight.bold, label: Text('굵게')),
                    ButtonSegment(
                        value: WatermarkWeight.black, label: Text('두껍게')),
                  ],
                  selected: {box.weight},
                  onSelectionChanged: (s) =>
                      onUpdate((b) => b.copyWith(weight: s.first)),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 폰트
          Row(
            children: [
              const Icon(Icons.font_download_outlined, size: 20),
              const SizedBox(width: 8),
              const Text('폰트', style: TextStyle(fontSize: 13)),
              const Spacer(),
              DropdownButton<WatermarkFont>(
                value: box.fontFamily,
                underline: const SizedBox.shrink(),
                items: [
                  for (final entry in const [
                    (WatermarkFont.sansSerif, '기본'),
                    (WatermarkFont.monospace, '모노스페이스'),
                    (WatermarkFont.serif, '세리프'),
                    (WatermarkFont.heavy, '두꺼운(헤비)'),
                  ])
                    DropdownMenuItem(
                      value: entry.$1,
                      child: Text(entry.$2,
                          style: TextStyle(
                              fontSize: 14,
                              fontFamily: _fontFamily(entry.$1),
                              color: Theme.of(context).colorScheme.onSurface)),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) onUpdate((b) => b.copyWith(fontFamily: v));
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 정렬
          Row(
            children: [
              const Icon(Icons.format_align_left, size: 20),
              const SizedBox(width: 8),
              const Text('정렬', style: TextStyle(fontSize: 13)),
              const Spacer(),
              SegmentedButton<WatermarkAlign>(
                segments: const [
                  ButtonSegment(
                      value: WatermarkAlign.left,
                      icon: Icon(Icons.format_align_left, size: 18)),
                  ButtonSegment(
                      value: WatermarkAlign.center,
                      icon: Icon(Icons.format_align_center, size: 18)),
                  ButtonSegment(
                      value: WatermarkAlign.right,
                      icon: Icon(Icons.format_align_right, size: 18)),
                ],
                selected: {box.alignment},
                onSelectionChanged: (s) =>
                    onUpdate((b) => b.copyWith(alignment: s.first)),
                style: const ButtonStyle(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 회전 (탭할 때마다 시계방향 90°)
          Row(
            children: [
              const Icon(Icons.rotate_90_degrees_cw, size: 20),
              const SizedBox(width: 8),
              const Text('회전', style: TextStyle(fontSize: 13)),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () => onUpdate(
                    (b) => b.copyWith(quarterTurns: (b.quarterTurns + 1) % 4)),
                icon: const Icon(Icons.rotate_90_degrees_cw, size: 16),
                label: Text('${box.quarterTurns * 90}°'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 글자색
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Icon(Icons.palette_outlined, size: 20),
              ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('글자색', style: TextStyle(fontSize: 13)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final c in WatermarkSettings.textPresets)
                      _Swatch(
                        color: Color(c),
                        selected: box.textColor == c,
                        onTap: () => onUpdate((b) => b.copyWith(textColor: c)),
                      ),
                    // 사용자 색상 히스토리(최신순)
                    for (final c in customColors)
                      _Swatch(
                        color: Color(c),
                        selected: box.textColor == c,
                        onTap: () => onUpdate((b) => b.copyWith(textColor: c)),
                      ),
                    // 현재 색이 프리셋/히스토리 어디에도 없으면 표시
                    if (!WatermarkSettings.textPresets.contains(box.textColor) &&
                        !customColors.contains(box.textColor))
                      _Swatch(
                        color: Color(box.textColor),
                        selected: true,
                        onTap: () => onPickColor(box.textColor),
                      ),
                    _ColorPickerButton(
                      initial: Color(box.textColor),
                      onPicked: onPickColor,
                    ),
                  ],
                ),
              ),
            ],
          ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── 색상 스와치 ───────────────────────────────────────────────

class _Swatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _Swatch(
      {required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? cs.primary : cs.outline.withValues(alpha: 0.4),
            width: selected ? 3 : 1,
          ),
        ),
        child: selected
            ? Icon(Icons.check,
                size: 16,
                color: color.computeLuminance() > 0.5
                    ? Colors.black
                    : Colors.white)
            : null,
      ),
    );
  }
}

// ── 컬러피커 버튼 (휠 기반 사용자 색상 선택) ──────────────────

class _ColorPickerButton extends StatelessWidget {
  final Color initial;
  final void Function(int color) onPicked;
  const _ColorPickerButton({required this.initial, required this.onPicked});

  /// 항상 불투명 ARGB로 정규화
  static int _argb(Color c) => 0xFF000000 | (c.toARGB32() & 0x00FFFFFF);

  Future<void> _open(BuildContext context) async {
    var picked = initial;
    final result = await showDialog<Color>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('색상 선택'),
        content: SingleChildScrollView(
          child: HueRingPicker(
            pickerColor: initial,
            onColorChanged: (c) => picked = c,
            enableAlpha: false,
            displayThumbColor: true,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, picked),
              child: const Text('선택')),
        ],
      ),
    );
    if (result != null) onPicked(_argb(result));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _open(context),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cs.surfaceContainerHighest,
          border: Border.all(color: cs.primary, width: 1.5),
        ),
        child: Icon(Icons.colorize, size: 16, color: cs.primary),
      ),
    );
  }
}

// ── 날짜/시간 형식 드롭다운 ────────────────────────────────────

class _FormatDropdown extends StatelessWidget {
  final String value;
  final List<String> options;
  final List<String>? labels;
  final void Function(String) onChanged;

  const _FormatDropdown({
    required this.value,
    required this.options,
    this.labels,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    return DropdownButton<String>(
      value: value,
      underline: const SizedBox.shrink(),
      isDense: true,
      style: TextStyle(fontSize: 12, color: textColor),
      items: options.asMap().entries.map((e) {
        final label = labels != null ? labels![e.key] : e.value;
        return DropdownMenuItem(
            value: e.value,
            child:
                Text(label, style: TextStyle(fontSize: 12, color: textColor)));
      }).toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

// ── 섹션 헤더 ─────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String label;
  const _Header(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
