import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../../core/constants/app_constants.dart';
import '../domain/models/outing_info.dart';

/// 날짜 화면 상단 '출조 정보' 요약 카드. 탭하면 편집 시트를 연다.
class OutingSummaryCard extends StatelessWidget {
  final OutingInfo? outing;
  final VoidCallback onTap;

  const OutingSummaryCard({super.key, required this.outing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final o = outing;
    final tackleCount = o?.tackles.where((t) => !t.isEmpty).length ?? 0;
    final catchStr = (o?.catches ?? const [])
        .where((c) => c.species.isNotEmpty)
        .map((c) => '${c.species} ${c.count}')
        .join(', ');
    final empty = o == null || o.isEmpty;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      color: cs.surfaceContainerHighest,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const Text('🎣', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: empty
                    ? Text('출조 정보 추가 (태클·조과)',
                        style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurface.withValues(alpha: 0.6)))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('태클 $tackleCount세트',
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          if (catchStr.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text('🐟 $catchStr',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color:
                                          cs.onSurface.withValues(alpha: 0.7))),
                            ),
                        ],
                      ),
              ),
              Icon(Icons.edit_outlined,
                  size: 18, color: cs.onSurface.withValues(alpha: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 출조 정보(태클 3세트 + 최종 조과) 편집 바텀시트.
class OutingEditSheet extends ConsumerStatefulWidget {
  final OutingInfo? initial;
  final Future<void> Function(OutingInfo) onSave;

  const OutingEditSheet({super.key, this.initial, required this.onSave});

  static Future<void> show(
    BuildContext context, {
    OutingInfo? initial,
    required Future<void> Function(OutingInfo) onSave,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxWidth: math.min(MediaQuery.of(context).size.width, 600),
      ),
      builder: (_) => OutingEditSheet(initial: initial, onSave: onSave),
    );
  }

  @override
  ConsumerState<OutingEditSheet> createState() => _OutingEditSheetState();
}

class _OutingEditSheetState extends ConsumerState<OutingEditSheet> {
  static const _maxTackles = 3;
  static const _maxCatches = 5;

  // 태클 3세트 × 4항목 컨트롤러
  late final List<Map<TackleField, TextEditingController>> _tackleCtrls;
  // 조과 행: (어종 컨트롤러, 마릿수)
  late List<(TextEditingController, int)> _catches;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _tackleCtrls = List.generate(_maxTackles, (i) {
      final t = (init != null && i < init.tackles.length)
          ? init.tackles[i]
          : const TackleSet();
      return {
        TackleField.rod: TextEditingController(text: t.rod),
        TackleField.reel: TextEditingController(text: t.reel),
        TackleField.line: TextEditingController(text: t.line),
        TackleField.rig: TextEditingController(text: t.rig),
      };
    });
    _catches = [
      for (final c in init?.catches ?? const <CatchTally>[])
        (TextEditingController(text: c.species), c.count),
    ];
  }

  @override
  void dispose() {
    for (final m in _tackleCtrls) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    for (final c in _catches) {
      c.$1.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom + mq.padding.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: math.min(mq.size.height * 0.92, 720)),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('출조 정보',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 4),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < _maxTackles; i++) ...[
                      _tackleSet(i),
                      const Divider(height: 20),
                    ],
                    _catchSection(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('취소'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('저장'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── 태클 세트 ─────────────────────────────────────────
  Widget _tackleSet(int index) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('태클 ${index + 1}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        _presetField(index, TackleField.rod, '로드'),
        const SizedBox(height: 6),
        _presetField(index, TackleField.reel, '릴'),
        const SizedBox(height: 6),
        _presetField(index, TackleField.line, '라인'),
        const SizedBox(height: 6),
        _presetField(index, TackleField.rig, '채비'),
      ],
    );
  }

  Widget _presetField(int setIndex, TackleField field, String label) {
    final presets =
        ref.watch(settingsProvider).valueOrNull?.tacklePresetsFor(field) ??
            const <String>[];
    final ctrl = _tackleCtrls[setIndex][field]!;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: ctrl,
            decoration: InputDecoration(
              labelText: label,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: const OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.arrow_drop_down, size: 24),
          tooltip: '$label 선택',
          enabled: presets.isNotEmpty,
          onSelected: (v) => setState(() => ctrl.text = v),
          itemBuilder: (_) => [
            for (final p in presets)
              PopupMenuItem<String>(
                value: p,
                child: Row(
                  children: [
                    Expanded(child: Text(p)),
                    InkWell(
                      onTap: () {
                        Navigator.pop(context); // 메뉴 닫기
                        ref
                            .read(settingsProvider.notifier)
                            .removeTacklePreset(field, p);
                      },
                      child: const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(Icons.close, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ── 최종 조과 ─────────────────────────────────────────
  Widget _catchSection() {
    final species = [
      ...(ref.watch(settingsProvider).valueOrNull?.visibleFishSpecies ??
          kCommonFishSpecies)
    ]..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('최종 조과',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const Spacer(),
            if (_catches.length < _maxCatches)
              TextButton.icon(
                onPressed: () => setState(() =>
                    _catches.add((TextEditingController(), 1))),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('추가'),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < _catches.length; i++) _catchRow(i, species),
      ],
    );
  }

  Widget _catchRow(int index, List<String> species) {
    final ctrl = _catches[index].$1;
    final count = _catches[index].$2;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Text('🐟', style: TextStyle(fontSize: 15)),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: '어종',
                hintText: '입력 또는 ▼',
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.arrow_drop_down, size: 24),
            tooltip: '어종 선택',
            onSelected: (v) => setState(() => ctrl.text = v),
            itemBuilder: (_) => species
                .map((s) => PopupMenuItem<String>(value: s, child: Text(s)))
                .toList(),
          ),
          // 마릿수 스테퍼
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            visualDensity: VisualDensity.compact,
            onPressed: count > 1
                ? () => setState(() =>
                    _catches[index] = (ctrl, count - 1))
                : null,
          ),
          Text('$count', style: const TextStyle(fontSize: 14)),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 20),
            visualDensity: VisualDensity.compact,
            onPressed: count < 999
                ? () => setState(() => _catches[index] = (ctrl, count + 1))
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() {
              _catches[index].$1.dispose();
              _catches.removeAt(index);
            }),
          ),
        ],
      ),
    );
  }

  // ── 저장 ──────────────────────────────────────────────
  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final notifier = ref.read(settingsProvider.notifier);
      final tackles = <TackleSet>[];
      for (final m in _tackleCtrls) {
        final rod = m[TackleField.rod]!.text.trim();
        final reel = m[TackleField.reel]!.text.trim();
        final line = m[TackleField.line]!.text.trim();
        final rig = m[TackleField.rig]!.text.trim();
        final set = TackleSet(rod: rod, reel: reel, line: line, rig: rig);
        tackles.add(set);
        // 새 값은 프리셋에 추가(중복 무시)
        if (rod.isNotEmpty) await notifier.addTacklePreset(TackleField.rod, rod);
        if (reel.isNotEmpty) {
          await notifier.addTacklePreset(TackleField.reel, reel);
        }
        if (line.isNotEmpty) {
          await notifier.addTacklePreset(TackleField.line, line);
        }
        if (rig.isNotEmpty) await notifier.addTacklePreset(TackleField.rig, rig);
      }
      final catches = <CatchTally>[];
      for (final c in _catches) {
        final sp = c.$1.text.trim();
        if (sp.isEmpty) continue;
        catches.add(CatchTally(species: sp, count: c.$2));
        await notifier.addFishSpecies(sp);
      }
      await widget.onSave(OutingInfo(tackles: tackles, catches: catches));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('저장 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
