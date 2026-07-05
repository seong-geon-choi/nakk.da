/// 어종 인식 추론 결과 한 건 — 어종명과 확률.
class SpeciesPrediction {
  final String species;
  final double confidence; // 0.0 ~ 1.0 (softmax 확률)

  const SpeciesPrediction({required this.species, required this.confidence});

  int get percent => (confidence * 100).round();
}
