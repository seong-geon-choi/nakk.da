import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../tide/domain/models/tide_station.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/tide_curve_graph.dart';
import '../domain/models/outing_info.dart';

/// 출조일을 연-월-일(요일) 형태로 포맷 (예: 2026-07-03(금)).
String _fmtOutingDate(DateTime d) {
  const wd = ['월', '화', '수', '목', '금', '토', '일'];
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '${d.year}-$mm-$dd(${wd[d.weekday - 1]})';
}

/// 날짜 화면 상단 '출조 정보' 요약 카드. 탭하면 편집 시트를 연다.
class OutingSummaryCard extends StatelessWidget {
  final OutingInfo? outing;
  final DateTime? date;
  final VoidCallback onTap;

  const OutingSummaryCard(
      {super.key, required this.outing, this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final o = outing;
    final tackleCount = o?.tackles.where((t) => !t.isEmpty).length ?? 0;
    final catchStr = (o?.catches ?? const [])
        .where((c) => c.species.isNotEmpty)
        .map((c) => '${c.species} ${c.count}')
        .join(', ');
    final v = o?.vessel;
    final vesselStr = (v != null && !v.isEmpty)
        ? [
            if (v.name.isNotEmpty) v.name,
            if (v.rating > 0) '★${v.rating}',
          ].join(' ')
        : '';
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('출조정보 (선박/태클/조과)',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: cs.primary)),
                        ),
                        if (date != null)
                          Text('🗓 ${_fmtOutingDate(date!)}',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      cs.onSurface.withValues(alpha: 0.7))),
                      ],
                    ),
                    if (empty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('탭하여 추가',
                            style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurface.withValues(alpha: 0.6))),
                      )
                    else ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                            vesselStr.isNotEmpty
                                ? '⛴ $vesselStr · 태클 $tackleCount세트'
                                : '태클 $tackleCount세트',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
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
  final DateTime? date; // 출조일(.md 파일 날짜)
  final List<TideEvent> tides; // 당일 물때(조위 그래프용)
  final String? tideName; // 당일 물때명(예: 3물)
  final Future<void> Function(OutingInfo) onSave;

  const OutingEditSheet({
    super.key,
    this.initial,
    this.date,
    this.tides = const [],
    this.tideName,
    required this.onSave,
  });

  static Future<void> show(
    BuildContext context, {
    OutingInfo? initial,
    DateTime? date,
    List<TideEvent> tides = const [],
    String? tideName,
    required Future<void> Function(OutingInfo) onSave,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxWidth: math.min(MediaQuery.of(context).size.width, 600),
      ),
      builder: (_) => OutingEditSheet(
          initial: initial,
          date: date,
          tides: tides,
          tideName: tideName,
          onSave: onSave),
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

  // 선사 정보
  final _vName = TextEditingController();
  final _vPort = TextEditingController();
  final _vPoint = TextEditingController();
  final _vFishType = TextEditingController();
  final _vDepth = TextEditingController();
  final _vReview = TextEditingController();
  int _departMin = 300;
  int _arriveMin = 960;
  int _rating = 0;
  int _tackleVisible = 1; // 화면에 표시할 태클 세트 수(+ 버튼으로 증가)
  final _scrollCtrl = ScrollController();
  bool _vesselExpanded = true;
  bool _tackleExpanded = true;
  bool _catchExpanded = true;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _tackleVisible =
        (init?.tackles.where((t) => !t.isEmpty).length ?? 1).clamp(1, _maxTackles);
    final v = init?.vessel;
    if (v != null) {
      _vName.text = v.name;
      _vPort.text = v.port;
      _vPoint.text = v.point;
      _vFishType.text = v.fishType;
      if (v.avgDepth != null) _vDepth.text = _fmtDepth(v.avgDepth!);
      _vReview.text = v.review;
      _departMin = v.departMin;
      _arriveMin = v.arriveMin;
      _rating = v.rating;
    }
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
    _vName.dispose();
    _vPort.dispose();
    _vPoint.dispose();
    _vFishType.dispose();
    _vDepth.dispose();
    _vReview.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  static String _fmtDepth(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  static String _minToHhmm(int min) {
    final h = (min ~/ 60).toString().padLeft(2, '0');
    final m = (min % 60).toString().padLeft(2, '0');
    return '$h:$m';
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
            if (widget.date != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('🗓 출조일  ${_fmtOutingDate(widget.date!)}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary)),
                ),
              ),
            const SizedBox(height: 4),
            Flexible(
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _expandable(
                      title: '선사 정보',
                      expanded: _vesselExpanded,
                      onToggle: () => setState(
                          () => _vesselExpanded = !_vesselExpanded),
                      child: _vesselSection(),
                    ),
                    _expandable(
                      title: '태클 정보',
                      expanded: _tackleExpanded,
                      onToggle: () => setState(
                          () => _tackleExpanded = !_tackleExpanded),
                      child: _tackleBody(),
                    ),
                    _expandable(
                      title: '최종 조과',
                      expanded: _catchExpanded,
                      onToggle: () =>
                          setState(() => _catchExpanded = !_catchExpanded),
                      child: _catchSection(),
                    ),
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

  /// 접기/펼치기 가능한 섹션(제목 헤더 + 본문). 제목은 강조색.
  Widget _expandable({
    required String title,
    required bool expanded,
    required VoidCallback onToggle,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                _sectionTitle(title),
                const Spacer(),
                Icon(expanded ? Icons.expand_less : Icons.expand_more,
                    size: 22, color: Theme.of(context).colorScheme.primary),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: child,
          ),
        const Divider(height: 1, thickness: 1.2),
      ],
    );
  }

  // ── 태클 세트 ─────────────────────────────────────────
  Widget _tackleBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _tackleVisible; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _tackleSet(i),
        ],
        if (_tackleVisible < _maxTackles)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                setState(() => _tackleVisible++);
                _scrollToEnd();
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('태클 추가'),
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            ),
          ),
      ],
    );
  }

  Widget _tackleSet(int index) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('태클 ${index + 1}',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: _presetField(index, TackleField.rod, '로드')),
            const SizedBox(width: 8),
            Expanded(child: _presetField(index, TackleField.reel, '릴')),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: _presetField(index, TackleField.line, '라인')),
            const SizedBox(width: 8),
            Expanded(child: _presetField(index, TackleField.rig, '채비')),
          ],
        ),
      ],
    );
  }

  Widget _presetField(int setIndex, TackleField field, String label) {
    final presets =
        ref.watch(settingsProvider).valueOrNull?.tacklePresetsFor(field) ??
            const <String>[];
    return _presetRow(
      ctrl: _tackleCtrls[setIndex][field]!,
      label: label,
      presets: presets,
      onRemovePreset: (p) =>
          ref.read(settingsProvider.notifier).removeTacklePreset(field, p),
    );
  }

  /// 모든 입력창 공용 데코레이션(높이·패딩·suffix 제약 통일).
  InputDecoration _fieldDec(String label, {Widget? suffix, String? hint}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        border: const OutlineInputBorder(),
        suffixIcon: suffix,
        suffixIconConstraints:
            const BoxConstraints(minWidth: 32, minHeight: 24),
      );

  /// 자유입력 TextField + 프리셋 드롭다운(입력창 안 ▼, 항목별 X 삭제) 공용 위젯
  Widget _presetRow({
    required TextEditingController ctrl,
    required String label,
    required List<String> presets,
    required void Function(String) onRemovePreset,
  }) {
    return TextField(
      controller: ctrl,
      decoration: _fieldDec(label,
          suffix: _presetDropdown(ctrl, label, presets, onRemovePreset)),
      style: const TextStyle(fontSize: 13),
    );
  }

  Widget _presetDropdown(TextEditingController ctrl, String label,
          List<String> presets, void Function(String) onRemovePreset) =>
      PopupMenuButton<String>(
        // icon: 대신 child: 사용 → 내부 IconButton(48px 최소높이) 제거해 필드 높이 통일
        tooltip: '$label 선택',
        enabled: presets.isNotEmpty,
        padding: EdgeInsets.zero,
        onSelected: (v) => setState(() => ctrl.text = v),
        child: Icon(Icons.arrow_drop_down,
            size: 24,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: presets.isEmpty ? 0.25 : 0.7)),
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
                      onRemovePreset(p);
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
      );

  /// 강조된 섹션 제목(색상)
  Widget _sectionTitle(String t) => Text(t,
      style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary));

  // ── 선사 정보 ─────────────────────────────────────────
  Widget _vesselSection() {
    final s = ref.watch(settingsProvider).valueOrNull;
    Widget vesselField(
            VesselField f, TextEditingController ctrl, String label) =>
        _presetRow(
          ctrl: ctrl,
          label: label,
          presets: s?.vesselPresetsFor(f) ?? const [],
          onRemovePreset: (p) =>
              ref.read(settingsProvider.notifier).removeVesselPreset(f, p),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: vesselField(VesselField.name, _vName, '선박명')),
            const SizedBox(width: 8),
            Expanded(child: vesselField(VesselField.port, _vPort, '항구')),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
                child: _timeField(
                    '출항', _departMin, (m) => setState(() => _departMin = m))),
            const SizedBox(width: 8),
            Expanded(
                child: _timeField(
                    '입항', _arriveMin, (m) => setState(() => _arriveMin = m))),
          ],
        ),
        const SizedBox(height: 10),
        _tideBlock(),
        const SizedBox(height: 10),
        vesselField(VesselField.point, _vPoint, '주요 포인트'),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: vesselField(VesselField.fishType, _vFishType, '낚시 종류')),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _vDepth,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: _fieldDec('평균 수심(m)'),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('별점', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 8),
            for (var i = 1; i <= 5; i++)
              GestureDetector(
                onTap: () =>
                    setState(() => _rating = _rating == i ? i - 1 : i),
                child: Icon(
                  i <= _rating ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                  size: 26,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _vReview,
          minLines: 3,
          maxLines: 5,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(
            labelText: '나의 평가',
            alignLabelWithHint: true,
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            border: OutlineInputBorder(),
          ),
          style: const TextStyle(fontSize: 13),
        ),
      ],
    );
  }

  /// 물때 요약(한 줄) + 조위 곡선. 물때 자료 없으면 그래프 위젯이 안내 표시.
  Widget _tideBlock() {
    final summary = _tideSummary();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (summary != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('🌊 $summary', style: const TextStyle(fontSize: 13)),
          ),
        TideCurveGraph(
          tides: widget.tides,
          startMin: _departMin,
          endMin: _arriveMin,
        ),
      ],
    );
  }

  String? _tideSummary() {
    if (widget.tides.isEmpty) return null;
    final parts = <String>[
      if (widget.tideName != null && widget.tideName!.trim().isNotEmpty)
        widget.tideName!.trim(),
      ...widget.tides.map((t) => '${t.type} ${t.time}'),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Widget _timeField(String label, int min, void Function(int) onChanged) {
    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: min ~/ 60, minute: min % 60),
        );
        if (picked != null) onChanged(picked.hour * 60 + picked.minute);
      },
      child: InputDecorator(
        decoration: _fieldDec(label),
        child: SizedBox(
          width: double.infinity,
          child: Text(_minToHhmm(min),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13)),
        ),
      ),
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
        for (var i = 0; i < _catches.length; i++) _catchRow(i, species),
        if (_catches.length < _maxCatches)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                setState(() => _catches.add((TextEditingController(), 1)));
                _scrollToEnd();
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('조과 추가'),
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            ),
          ),
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
          const Text('🐟', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: ctrl,
              decoration: _fieldDec(
                '어종',
                hint: '입력 또는 ▼',
                suffix: PopupMenuButton<String>(
                  tooltip: '어종 선택',
                  padding: EdgeInsets.zero,
                  enabled: species.isNotEmpty,
                  onSelected: (v) => setState(() => ctrl.text = v),
                  child: Icon(Icons.arrow_drop_down,
                      size: 24,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: species.isEmpty ? 0.25 : 0.7)),
                  itemBuilder: (_) => species
                      .map((s) =>
                          PopupMenuItem<String>(value: s, child: Text(s)))
                      .toList(),
                ),
              ),
              style: const TextStyle(fontSize: 13),
            ),
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
          Text('$count', style: const TextStyle(fontSize: 13)),
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

      // 선사 정보
      final vName = _vName.text.trim();
      final vPort = _vPort.text.trim();
      final vPoint = _vPoint.text.trim();
      final vFishType = _vFishType.text.trim();
      final vessel = VesselInfo(
        name: vName,
        port: vPort,
        departMin: _departMin,
        arriveMin: _arriveMin,
        point: vPoint,
        fishType: vFishType,
        avgDepth: double.tryParse(_vDepth.text.trim()),
        rating: _rating,
        review: _vReview.text.trim(),
      );
      if (vName.isNotEmpty) await notifier.addVesselPreset(VesselField.name, vName);
      if (vPort.isNotEmpty) await notifier.addVesselPreset(VesselField.port, vPort);
      if (vPoint.isNotEmpty) {
        await notifier.addVesselPreset(VesselField.point, vPoint);
      }
      if (vFishType.isNotEmpty) {
        await notifier.addVesselPreset(VesselField.fishType, vFishType);
      }

      await widget.onSave(
          OutingInfo(tackles: tackles, catches: catches, vessel: vessel));
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
