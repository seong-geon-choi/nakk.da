import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/species_recognizer.dart';

/// 앱 생애 동안 한 번 로드되는 공유 어종 인식기.
/// 모델 파일(assets/model/)이 없으면 null을 반환한다(기능 비활성).
final speciesRecognizerProvider = FutureProvider<SpeciesRecognizer?>((ref) async {
  final rec = SpeciesRecognizer();
  try {
    await rec.load();
  } catch (_) {
    return null;
  }
  ref.onDispose(rec.close);
  return rec;
});
