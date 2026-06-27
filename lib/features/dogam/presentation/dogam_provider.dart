import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../search/presentation/search_provider.dart';
import '../../settings/presentation/settings_provider.dart';
import '../domain/models/dogam_entry.dart';

/// 도감 항목 목록. 대상 어종은 설정의 어종 목록(사용자 편집 가능)을 따른다.
/// 표시 순서는 어종명 가나다(ㄱ~ㅎ)순. 한글 음절은 코드포인트가 초성 순으로
/// 배열돼 있어 기본 문자열 비교(compareTo)가 곧 ㄱ~ㅎ 사전순이 된다.
final dogamProvider = Provider.autoDispose<AsyncValue<List<DogamEntry>>>((ref) {
  final species =
      ref.watch(settingsProvider).valueOrNull?.fishSpecies ?? kCommonFishSpecies;
  return ref.watch(searchHitsProvider).whenData((hits) {
    final entries = DogamEntry.build(species, hits);
    entries.sort((a, b) => a.species.compareTo(b.species));
    return entries;
  });
});
