import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/search_service.dart';
import '../domain/models/search_hit.dart';
import '../../settings/presentation/settings_provider.dart';

/// 검색 화면 진입 시 전체 메모 엔트리를 1회 로드 (autoDispose: 화면 이탈 시 해제)
final searchHitsProvider = FutureProvider.autoDispose<List<SearchHit>>((ref) async {
  final settings = await ref.watch(settingsProvider.future);
  return SearchService().loadAllHits(settings.savePath);
});
