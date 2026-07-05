import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/species_recognizer.dart';
import '../data/model_update_service.dart';
import '../domain/species_prediction.dart';

/// 어종 인식 모델 검증용 최소 테스트 화면.
/// 갤러리/촬영으로 사진 하나를 골라 상위 3개 후보를 표시한다.
/// (설정 → 버전 7연타 개발자 메뉴 → AI 어종 인식 테스트)
class SpeciesTestScreen extends StatefulWidget {
  const SpeciesTestScreen({super.key});

  @override
  State<SpeciesTestScreen> createState() => _SpeciesTestScreenState();
}

class _SpeciesTestScreenState extends State<SpeciesTestScreen> {
  final _recognizer = SpeciesRecognizer();
  final _picker = ImagePicker();

  bool _loading = true;
  bool _busy = false;
  String _status = '모델 로드 중...';
  String _modelInfo = '';
  File? _image;
  List<SpeciesPrediction> _results = const [];

  @override
  void initState() {
    super.initState();
    _loadModel();
    _loadModelInfo();
  }

  Future<void> _loadModelInfo() async {
    final s = await ModelUpdateService().currentStatus();
    if (!mounted) return;
    String two(int n) => n.toString().padLeft(2, '0');
    final d = s.updatedAt;
    final info = s.isRemote
        ? (d != null
            ? '모델: 원격 · ${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}'
            : '모델: 원격')
        : '모델: 번들(기본)';
    setState(() => _modelInfo = info);
  }

  Future<void> _showTrainStats() async {
    final stats = await ModelUpdateService().fetchTrainStats();
    if (!mounted) return;
    if (stats == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('학습 데이터 현황을 불러올 수 없습니다.')),
      );
      return;
    }
    final total = stats['total'];
    final perSpecies = (stats['perSpecies'] as Map?) ?? const {};
    final entries = perSpecies.entries.toList()
      ..sort((a, b) => (b.value as num).compareTo(a.value as num));
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('학습 데이터 현황 (총 $total장)'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final e in entries)
                ListTile(
                  dense: true,
                  title: Text('${e.key}'),
                  trailing: Text('${e.value}장'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadModel() async {
    try {
      await _recognizer.load();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = '사진을 선택하면 어종 후보를 추론합니다.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = '모델 로드 실패\n'
            'assets/model/ 에 fish_model.tflite·labels.txt 를 넣었나요?\n\n$e';
      });
    }
  }

  Future<void> _pick(ImageSource src) async {
    if (!_recognizer.isReady || _busy) return;
    final x = await _picker.pickImage(source: src);
    if (x == null) return;
    setState(() {
      _image = File(x.path);
      _results = const [];
      _busy = true;
      _status = '추론 중...';
    });
    try {
      final r = await _recognizer.classify(_image!);
      if (!mounted) return;
      setState(() {
        _results = r;
        _busy = false;
        _status = '완료';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '추론 실패: $e';
      });
    }
  }

  @override
  void dispose() {
    _recognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canPick = _recognizer.isReady && !_busy;
    return Scaffold(
      appBar: AppBar(title: const Text('AI 어종 인식 테스트')),
      body: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_modelInfo.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(_modelInfo,
                          style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                    ),
                    TextButton(
                      onPressed: _showTrainStats,
                      child: const Text('학습 데이터 현황'),
                    ),
                  ],
                ),
              ),
            if (_loading) const LinearProgressIndicator(),
            if (_image != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(_image!, height: 220, fit: BoxFit.cover),
              ),
              const SizedBox(height: 12),
            ],
            Text(_status),
            const SizedBox(height: 16),
            for (final p in _results) _ResultBar(p),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: canPick ? () => _pick(ImageSource.gallery) : null,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('갤러리'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: canPick ? () => _pick(ImageSource.camera) : null,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('촬영'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultBar extends StatelessWidget {
  final SpeciesPrediction p;
  const _ResultBar(this.p);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(p.species,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: p.confidence, minHeight: 12),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            child: Text('${p.percent}%', textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}
