import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../location/domain/models/location_status.dart';
import '../../settings/presentation/settings_provider.dart';
import 'memo_provider.dart';

class LocationEditSheet extends ConsumerStatefulWidget {
  final LocationStatus existing;
  final int blockIndex;
  final Future<void> Function(int blockIndex, LocationStatus updated)? onEditSave;

  const LocationEditSheet({
    super.key,
    required this.existing,
    required this.blockIndex,
    this.onEditSave,
  });

  static Future<void> show(
    BuildContext context, {
    required LocationStatus existing,
    required int blockIndex,
    Future<void> Function(int, LocationStatus)? onEditSave,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxWidth: math.min(MediaQuery.of(context).size.width, 600),
      ),
      builder: (_) => LocationEditSheet(
        existing: existing,
        blockIndex: blockIndex,
        onEditSave: onEditSave,
      ),
    );
  }

  @override
  ConsumerState<LocationEditSheet> createState() => _LocationEditSheetState();
}

class _LocationEditSheetState extends ConsumerState<LocationEditSheet> {
  late final TextEditingController _address;
  late final TextEditingController _temp;
  late final TextEditingController _tideName;
  late final TextEditingController _tideTime;
  late final TextEditingController _waterTemp;
  late final TextEditingController _stationName;
  late final TextEditingController _stationDist;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _address = TextEditingController(text: e.address ?? '');
    _temp = TextEditingController(text: e.temperature?.toString() ?? '');
    _tideName = TextEditingController(text: e.tideName ?? '');
    _tideTime = TextEditingController(text: e.tideTime ?? '');
    _waterTemp = TextEditingController(text: e.waterTemp?.toString() ?? '');
    _stationName = TextEditingController(text: e.stationName ?? '');
    _stationDist = TextEditingController(
        text: e.stationDistance?.toStringAsFixed(1) ?? '');
  }

  @override
  void dispose() {
    _address.dispose();
    _temp.dispose();
    _tideName.dispose();
    _tideTime.dispose();
    _waterTemp.dispose();
    _stationName.dispose();
    _stationDist.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom + mq.padding.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: math.min(mq.size.height * 0.85, 650)),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('현황 수정',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _field('📍 주소', _address),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _field('🌡 기온 (°C)', _temp,
                    inputType: const TextInputType.numberWithOptions(decimal: true, signed: true))),
                const SizedBox(width: 8),
                Expanded(child: _field('💧 수온 (°C)', _waterTemp,
                    inputType: const TextInputType.numberWithOptions(decimal: true, signed: true))),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _field('🌊 물때', _tideName)),
                const SizedBox(width: 8),
                Expanded(child: _field('조석 (예: 만조 18:03)', _tideTime)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _field('관측소명', _stationName)),
                const SizedBox(width: 8),
                Expanded(child: _field('거리 (km)', _stationDist,
                    inputType: const TextInputType.numberWithOptions(decimal: true))),
              ]),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('취소'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('저장'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {TextInputType? inputType}) {
    return TextField(
      controller: ctrl,
      keyboardType: inputType,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      style: const TextStyle(fontSize: 14),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final e = widget.existing;
      final updated = LocationStatus(
        timestamp: e.timestamp,
        latitude: e.latitude,
        longitude: e.longitude,
        isMove: e.isMove,
        address: _address.text.trim().isEmpty ? null : _address.text.trim(),
        temperature: double.tryParse(_temp.text.trim()),
        tideName: _tideName.text.trim().isEmpty ? null : _tideName.text.trim(),
        tideTime: _tideTime.text.trim().isEmpty ? null : _tideTime.text.trim(),
        waterTemp: double.tryParse(_waterTemp.text.trim()),
        stationName: _stationName.text.trim().isEmpty ? null : _stationName.text.trim(),
        stationDistance: double.tryParse(_stationDist.text.trim()),
        tides: e.tides,
      );
      if (widget.onEditSave != null) {
        await widget.onEditSave!(widget.blockIndex, updated);
      } else {
        final savePath = ref.read(settingsProvider).valueOrNull?.savePath ?? '';
        await ref
            .read(dayFileProvider(todayMemoFilePath(savePath)).notifier)
            .editBlock(widget.blockIndex, updated);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
