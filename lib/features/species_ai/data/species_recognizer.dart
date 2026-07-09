import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../domain/species_prediction.dart';
import 'model_update_service.dart';

/// 온디바이스 어종 인식기.
///
/// Colab 학습 노트북(`tools/train_fish_model.ipynb`)이 내보낸 TFLite 모델을 로드해
/// 사진에서 어종 후보를 추론한다.
///
/// 모델 입력 사양(노트북 셀11): 224×224×3, RGB, float32, 픽셀값 **0~255 그대로**
/// (정규화는 모델 내부의 preprocess_input이 담당하므로 여기선 스케일링하지 않는다).
class SpeciesRecognizer {
  static const _modelAsset = 'assets/model/fish_model.tflite';
  static const _labelsAsset = 'assets/model/labels.txt';
  static const int _inputSize = 224;

  Interpreter? _interpreter;
  List<String> _labels = const [];
  int _numClasses = 0;

  bool get isReady => _interpreter != null && _numClasses > 0;

  /// 모델·라벨을 로드한다. OTA로 내려받은 로컬 파일을 우선 사용하고,
  /// 없거나 손상됐으면 번들 에셋으로 폴백한다.
  ///
  /// 로컬 파일을 읽기 전에 진행 중인 OTA 체크(main.dart에서 이미 시작됨)를
  /// 기다려, 새 모델이 나온 콜드 스타트 안에서 바로 반영되게 한다.
  Future<void> load() async {
    await ModelUpdateService().checkAndUpdate();
    if (await _tryLoadLocal()) return;
    await _loadFromAsset();
  }

  Future<bool> _tryLoadLocal() async {
    try {
      final mf = await ModelUpdateService.localModelFile();
      final lf = await ModelUpdateService.localLabelsFile();
      if (!await mf.exists() || !await lf.exists()) return false;
      final interp = Interpreter.fromBuffer(await mf.readAsBytes());
      final labels = _parseLabels(await lf.readAsString());
      if (labels.isEmpty) {
        interp.close();
        return false;
      }
      _interpreter = interp;
      _labels = labels;
      _numClasses = labels.length;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadFromAsset() async {
    final modelData = await rootBundle.load(_modelAsset);
    _interpreter = Interpreter.fromBuffer(modelData.buffer.asUint8List());
    _labels = _parseLabels(await rootBundle.loadString(_labelsAsset));
    _numClasses = _labels.length;
  }

  List<String> _parseLabels(String raw) => raw
      .split('\n')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  /// 이미지 파일에서 상위 [topK]개 어종 후보를 확률 내림차순으로 반환.
  Future<List<SpeciesPrediction>> classify(File file, {int topK = 3}) async {
    return classifyBytes(await file.readAsBytes(), topK: topK);
  }

  /// 이미지 바이트에서 상위 [topK]개 어종 후보를 확률 내림차순으로 반환.
  /// (SAF content:// 사진처럼 File이 아닌 경우에 사용)
  Future<List<SpeciesPrediction>> classifyBytes(Uint8List bytes,
      {int topK = 3}) async {
    final interpreter = _interpreter;
    if (interpreter == null || _numClasses == 0) {
      throw StateError('모델이 로드되지 않았습니다. load()를 먼저 호출하세요.');
    }

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('이미지를 디코드할 수 없습니다.');
    }
    // 폰카/갤러리 사진의 EXIF 회전을 실제 픽셀에 반영(안 하면 눕혀진 이미지가 추론됨).
    final oriented = img.bakeOrientation(decoded);
    final resized =
        img.copyResize(oriented, width: _inputSize, height: _inputSize);

    // 입력 텐서 [1, 224, 224, 3] — RGB, 0~255 float
    final input = List.generate(
      1,
      (_) => List.generate(
        _inputSize,
        (y) => List.generate(_inputSize, (x) {
          final p = resized.getPixel(x, y);
          return [p.r.toDouble(), p.g.toDouble(), p.b.toDouble()];
        }),
      ),
    );

    final output = List.filled(_numClasses, 0.0).reshape([1, _numClasses]);
    interpreter.run(input, output);
    final scores = (output[0] as List).cast<double>();

    final order = List<int>.generate(_numClasses, (i) => i)
      ..sort((a, b) => scores[b].compareTo(scores[a]));
    return order
        .take(topK)
        .map((i) => SpeciesPrediction(species: _labels[i], confidence: scores[i]))
        .toList();
  }

  void close() {
    _interpreter?.close();
    _interpreter = null;
    _numClasses = 0;
  }
}
