import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'settings_provider.dart';
import '../domain/models/app_settings.dart';

class WatermarkSettingsScreen extends ConsumerStatefulWidget {
  const WatermarkSettingsScreen({super.key});

  @override
  ConsumerState<WatermarkSettingsScreen> createState() =>
      _WatermarkSettingsScreenState();
}

class _WatermarkSettingsScreenState
    extends ConsumerState<WatermarkSettingsScreen> {
  late TextEditingController _customCtrl;
  bool _darkPreview = false;
  bool _portraitPreview = true;

  @override
  void initState() {
    super.initState();
    final wm = ref.read(settingsProvider).valueOrNull?.watermark;
    final customText = wm?.lines
            .firstWhere((l) => l.type == WatermarkLineType.customText,
                orElse: () =>
                    const WatermarkLine(type: WatermarkLineType.customText))
            .customText ??
        '';
    _customCtrl = TextEditingController(text: customText);
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  void _update(WatermarkSettings updated) =>
      ref.read(settingsProvider.notifier).updateWatermark(updated);

  @override
  Widget build(BuildContext context) {
    final wm = ref.watch(settingsProvider).valueOrNull?.watermark ??
        WatermarkSettings();

    return Scaffold(
      appBar: AppBar(title: const Text('워터마크 설정')),
      body: Column(
        children: [
          // ── 고정 미리보기 영역 ─────────────────────────
          _PreviewSection(
            wm: wm,
            dark: _darkPreview,
            isPortrait: _portraitPreview,
            onToggleBg: (v) => setState(() => _darkPreview = v),
            onToggleOrientation: (v) => setState(() => _portraitPreview = v),
          ),
          const Divider(height: 1),

          // ── 스크롤 설정 영역 ───────────────────────────
          Expanded(
            child: ListView(
              children: [
                // 활성화
                SwitchListTile(
                  secondary: const Icon(Icons.water_outlined),
                  title: const Text('워터마크 활성화'),
                  subtitle: const Text('카메라 촬영 사진에 날짜·시간을 삽입합니다'),
                  value: wm.enabled,
                  onChanged: (v) => _update(wm.copyWith(enabled: v)),
                ),
                const Divider(height: 1),

                // 박스 위치
                _Header('박스 위치'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: _PositionGrid(
                    selected: wm.position,
                    onSelect: (p) => _update(wm.copyWith(position: p)),
                  ),
                ),
                const Divider(height: 1),

                // 표시 항목 및 순서
                _Header('표시 항목 및 순서  (길게 눌러 순서 변경)'),
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  onReorder: (oldIdx, newIdx) {
                    final lines = List<WatermarkLine>.from(wm.lines);
                    if (newIdx > oldIdx) newIdx--;
                    lines.insert(newIdx, lines.removeAt(oldIdx));
                    _update(wm.copyWith(lines: lines));
                  },
                  children: [
                    for (var i = 0; i < wm.lines.length; i++)
                      _buildLineRow(context, wm, i),
                  ],
                ),
                const Divider(height: 1),

                // 글자·박스 설정
                _Header('글자 설정'),
                _FontSettings(wm: wm, onUpdate: _update),
                const Divider(indent: 16, endIndent: 16, height: 24),

                // 박스 투명도
                _Header('박스 투명도'),
                ListTile(
                  leading: const Icon(Icons.opacity),
                  title: const Text('배경 박스 투명도'),
                  trailing: Text(
                    '${(wm.boxOpacity * 100).round()}%',
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Slider(
                    value: wm.boxOpacity,
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    label: '${(wm.boxOpacity * 100).round()}%',
                    onChanged: (v) => _update(wm.copyWith(boxOpacity: v)),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineRow(BuildContext context, WatermarkSettings wm, int i) {
    final line = wm.lines[i];
    return ListTile(
      key: ValueKey('wm_${line.type.name}'),
      contentPadding: const EdgeInsets.only(left: 8, right: 8),
      leading: ReorderableDragStartListener(
        index: i,
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.drag_handle, size: 20),
        ),
      ),
      title: line.type == WatermarkLineType.customText
          ? TextField(
              controller: _customCtrl,
              decoration: const InputDecoration(
                hintText: '커스텀 텍스트 입력',
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              style: const TextStyle(fontSize: 14),
              onChanged: (text) {
                final lines = List<WatermarkLine>.from(wm.lines);
                lines[i] = line.copyWith(customText: text);
                _update(wm.copyWith(lines: lines));
              },
            )
          : Row(
              children: [
                Text(_lineLabel(line.type),
                    style: const TextStyle(fontSize: 14)),
                const Spacer(),
                if (line.type == WatermarkLineType.date)
                  _FormatDropdown(
                    value: wm.dateFormat,
                    options: const ['yyyy-MM-dd', 'yy/MM/dd', 'MM/dd'],
                    onChanged: (v) => _update(wm.copyWith(dateFormat: v)),
                  )
                else if (line.type == WatermarkLineType.time)
                  _FormatDropdown(
                    value: wm.timeFormat,
                    options: const ['HH:mm', 'HH:mm:ss', ''],
                    labels: const ['HH:mm', 'HH:mm:ss', '없음'],
                    onChanged: (v) => _update(wm.copyWith(timeFormat: v)),
                  ),
                const SizedBox(width: 4),
              ],
            ),
      trailing: Switch(
        value: line.visible,
        onChanged: (v) {
          final lines = List<WatermarkLine>.from(wm.lines);
          lines[i] = line.copyWith(visible: v);
          _update(wm.copyWith(lines: lines));
        },
      ),
    );
  }

  String _lineLabel(WatermarkLineType type) => switch (type) {
        WatermarkLineType.date => '📅 날짜',
        WatermarkLineType.time => '🕐 시간',
        WatermarkLineType.customText => '📝 텍스트',
      };
}

// ── 고정 미리보기 섹션 ─────────────────────────────────────────

class _PreviewSection extends StatelessWidget {
  final WatermarkSettings wm;
  final bool dark;
  final bool isPortrait;
  final void Function(bool) onToggleBg;
  final void Function(bool) onToggleOrientation;

  const _PreviewSection({
    required this.wm,
    required this.dark,
    required this.isPortrait,
    required this.onToggleBg,
    required this.onToggleOrientation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 제목 + 배경 토글
          Row(
            children: [
              Text('미리보기',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary)),
              const Spacer(),
              _BgToggle(dark: dark, onChanged: onToggleBg),
            ],
          ),
          const SizedBox(height: 6),
          // 방향 토글
          Row(
            children: [
              _Chip(
                label: '세로',
                icon: Icons.stay_current_portrait,
                selected: isPortrait,
                onTap: () => onToggleOrientation(true),
              ),
              const SizedBox(width: 6),
              _Chip(
                label: '가로',
                icon: Icons.stay_current_landscape,
                selected: !isPortrait,
                onTap: () => onToggleOrientation(false),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _WatermarkPreview(wm: wm, dark: dark, isPortrait: isPortrait),
        ],
      ),
    );
  }
}

// ── 배경 토글 버튼 ─────────────────────────────────────────────

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
              color:
                  selected ? cs.primary : cs.outline.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: selected
                    ? cs.primary
                    : cs.onSurface.withValues(alpha: 0.6)),
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

// ── 워터마크 미리보기 ──────────────────────────────────────────

class _WatermarkPreview extends StatelessWidget {
  final WatermarkSettings wm;
  final bool dark;
  final bool isPortrait;

  const _WatermarkPreview(
      {required this.wm, required this.dark, required this.isPortrait});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final lines = wm.lines
        .where((l) => l.visible)
        .map((l) => _lineText(l, now))
        .where((s) => s.isNotEmpty)
        .toList();

    final bgColor =
        dark ? const Color(0xFF1A1A2E) : const Color(0xFFE8EAF0);
    final hintColor = dark ? Colors.white24 : Colors.black26;
    final boxColor = Color.fromARGB(
        (wm.boxOpacity * 255).round().clamp(0, 255), 0, 0, 0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;

        // 사진 종횡비에 맞는 프리뷰 크기
        //   세로: 3:4 (width:height), 가로: 16:9
        final double previewW, previewH;
        if (isPortrait) {
          // 세로 사진: 가용 너비의 55%를 폭으로 사용해 세로로 긴 모양 표현
          previewW = maxW * 0.55;
          previewH = previewW * 4.0 / 3.0;
        } else {
          previewW = maxW;
          previewH = maxW * 9.0 / 16.0;
        }

        // 실제 applyWatermark 공식과 동일한 비례 계산
        // applyWatermark: scaledFont = fontSize × shortSide / 480
        // shortSide = min(imageW, imageH) ≈ 1080 (ResolutionPreset.high)
        // 비례 그대로 미리보기 shortSide 적용
        final shortSide = isPortrait ? previewW : previewH;
        final previewFont =
            (wm.fontSize * shortSide / 480.0).clamp(5.0, 40.0);

        final margin = previewFont * 0.5;

        Widget watermarkBox = Container(
          padding: EdgeInsets.symmetric(
            horizontal: previewFont * 0.5,
            vertical: previewFont * 0.3,
          ),
          decoration: BoxDecoration(
            color: boxColor,
            borderRadius: BorderRadius.circular(previewFont * 0.15),
          ),
          child: Column(
            crossAxisAlignment: _crossAlign(wm.alignment),
            mainAxisSize: MainAxisSize.min,
            children: lines
                .map((text) => Text(
                      text,
                      textAlign: _textAlign(wm.alignment),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: previewFont,
                        fontWeight:
                            wm.bold ? FontWeight.bold : FontWeight.normal,
                        fontFamily: _fontFamily(wm.fontFamily),
                        height: 1.35,
                      ),
                    ))
                .toList(),
          ),
        );

        final positioned = lines.isEmpty
            ? const SizedBox.shrink()
            : Positioned(
                top: _isTop(wm.position) ? margin : null,
                bottom: _isBottom(wm.position) ? margin : null,
                left: _isLeft(wm.position) ? margin : null,
                right: _isRight(wm.position) ? margin : null,
                child: watermarkBox,
              );

        // 세로 사진은 중앙 정렬, 가로는 전체 폭
        Widget frame = ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: previewW,
            height: previewH,
            child: Stack(
              children: [
                Container(color: bgColor),
                Center(
                    child: Icon(Icons.photo_camera_outlined,
                        size: previewH * 0.22, color: hintColor)),
                positioned,
                if (!wm.enabled)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black45,
                      child: const Center(
                        child: Text('워터마크 비활성화됨',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 13)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );

        return isPortrait
            ? Center(child: frame)
            : frame;
      },
    );
  }

  String _lineText(WatermarkLine line, DateTime now) {
    switch (line.type) {
      case WatermarkLineType.date:
        return _formatDate(now, wm.dateFormat);
      case WatermarkLineType.time:
        return wm.timeFormat.isEmpty ? '' : _formatTime(now, wm.timeFormat);
      case WatermarkLineType.customText:
        final t = line.customText.trim();
        return t.isEmpty ? '(커스텀 텍스트)' : t;
    }
  }

  String _formatDate(DateTime dt, String format) {
    final y = dt.year.toString();
    final yy = (dt.year % 100).toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    switch (format) {
      case 'yy/MM/dd':
        return '$yy/$mm/$dd';
      case 'MM/dd':
        return '$mm/$dd';
      default:
        return '$y-$mm-$dd';
    }
  }

  String _formatTime(DateTime dt, String format) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final sec = dt.second.toString().padLeft(2, '0');
    return format == 'HH:mm:ss' ? '$hh:$min:$sec' : '$hh:$min';
  }

  CrossAxisAlignment _crossAlign(WatermarkAlign a) => switch (a) {
        WatermarkAlign.left => CrossAxisAlignment.start,
        WatermarkAlign.center => CrossAxisAlignment.center,
        WatermarkAlign.right => CrossAxisAlignment.end,
      };

  TextAlign _textAlign(WatermarkAlign a) => switch (a) {
        WatermarkAlign.left => TextAlign.left,
        WatermarkAlign.center => TextAlign.center,
        WatermarkAlign.right => TextAlign.right,
      };

  String _fontFamily(WatermarkFont f) => switch (f) {
        WatermarkFont.monospace => 'monospace',
        WatermarkFont.serif => 'serif',
        WatermarkFont.sansSerif => 'sans-serif',
      };

  bool _isTop(WatermarkPosition p) =>
      p == WatermarkPosition.topLeft || p == WatermarkPosition.topRight;
  bool _isBottom(WatermarkPosition p) =>
      p == WatermarkPosition.bottomLeft || p == WatermarkPosition.bottomRight;
  bool _isLeft(WatermarkPosition p) =>
      p == WatermarkPosition.topLeft || p == WatermarkPosition.bottomLeft;
  bool _isRight(WatermarkPosition p) =>
      p == WatermarkPosition.topRight || p == WatermarkPosition.bottomRight;
}

// ── 박스 위치 선택기 ──────────────────────────────────────────

class _PositionGrid extends StatelessWidget {
  final WatermarkPosition selected;
  final void Function(WatermarkPosition) onSelect;

  const _PositionGrid({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(children: [
          _PosBtn('↖ 좌상', WatermarkPosition.topLeft, selected, onSelect),
          const SizedBox(width: 8),
          _PosBtn('우상 ↗', WatermarkPosition.topRight, selected, onSelect),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          _PosBtn('↙ 좌하', WatermarkPosition.bottomLeft, selected, onSelect),
          const SizedBox(width: 8),
          _PosBtn('우하 ↘', WatermarkPosition.bottomRight, selected, onSelect),
        ]),
      ],
    );
  }
}

class _PosBtn extends StatelessWidget {
  final String label;
  final WatermarkPosition pos;
  final WatermarkPosition selected;
  final void Function(WatermarkPosition) onSelect;

  const _PosBtn(this.label, this.pos, this.selected, this.onSelect);

  @override
  Widget build(BuildContext context) {
    final isSelected = pos == selected;
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: isSelected ? cs.primaryContainer : null,
          side: BorderSide(color: isSelected ? cs.primary : cs.outline),
          padding: const EdgeInsets.symmetric(vertical: 10),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: () => onSelect(pos),
        child: Text(label,
            style: TextStyle(
                fontSize: 13, color: isSelected ? cs.primary : null)),
      ),
    );
  }
}

// ── 폰트 설정 ─────────────────────────────────────────────────

class _FontSettings extends StatelessWidget {
  final WatermarkSettings wm;
  final void Function(WatermarkSettings) onUpdate;

  const _FontSettings({required this.wm, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.format_size),
          title: const Text('글자 크기'),
          trailing: Text('${wm.fontSize.toInt()}',
              style: const TextStyle(fontSize: 13)),
          subtitle: Slider(
            value: wm.fontSize,
            min: 16,
            max: 80,
            divisions: 16,
            label: wm.fontSize.toInt().toString(),
            onChanged: (v) => onUpdate(wm.copyWith(fontSize: v)),
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.format_bold),
          title: const Text('굵게'),
          value: wm.bold,
          onChanged: (v) => onUpdate(wm.copyWith(bold: v)),
        ),
        ListTile(
          leading: const Icon(Icons.format_align_left),
          title: const Text('정렬'),
          trailing: SegmentedButton<WatermarkAlign>(
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
            selected: {wm.alignment},
            onSelectionChanged: (s) =>
                onUpdate(wm.copyWith(alignment: s.first)),
            style: ButtonStyle(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: WidgetStateProperty.all(
                  const EdgeInsets.symmetric(horizontal: 8)),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.font_download_outlined),
          title: const Text('폰트'),
          trailing: DropdownButton<WatermarkFont>(
            value: wm.fontFamily,
            underline: const SizedBox.shrink(),
            items: [
              DropdownMenuItem(
                  value: WatermarkFont.sansSerif,
                  child: Text('기본',
                      style: TextStyle(
                          fontSize: 14,
                          color:
                              Theme.of(context).colorScheme.onSurface))),
              DropdownMenuItem(
                  value: WatermarkFont.monospace,
                  child: Text('모노스페이스',
                      style: TextStyle(
                          fontSize: 14,
                          color:
                              Theme.of(context).colorScheme.onSurface))),
              DropdownMenuItem(
                  value: WatermarkFont.serif,
                  child: Text('세리프',
                      style: TextStyle(
                          fontSize: 14,
                          color:
                              Theme.of(context).colorScheme.onSurface))),
            ],
            onChanged: (v) {
              if (v != null) onUpdate(wm.copyWith(fontFamily: v));
            },
          ),
        ),
      ],
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
            child: Text(label,
                style: TextStyle(fontSize: 12, color: textColor)));
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
