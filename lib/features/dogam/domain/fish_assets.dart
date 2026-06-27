/// 어종(한글) → 에셋 파일 키(로마자) 매핑.
/// 컬러 일러스트: `assets/fish/color/{key}-col.png`
/// 실루엣:       `assets/fish/silhouette/{key}-sil.png`
///
/// 키가 없거나 이미지 파일이 아직 없으면 화면에서 기본 아이콘으로 폴백한다.
/// (이미지를 추가하는 대로 점진적으로 반영됨)
const Map<String, String> kFishAssetKeys = {
  '감성돔': 'gamsungdom',
  '참돔': 'chamdom',
  '돌돔': 'doldom',
  '벵에돔': 'bengedom',
  '볼락': 'bollak',
  '우럭': 'ureok',
  '광어': 'gwangeo',
  '농어': 'nongeo',
  '민어': 'mineo',
  '망상어': 'mangsangeo',
  '학공치': 'hakgongchi',
  '숭어': 'sungeo',
  '전갱이': 'jeongaengi',
  '고등어': 'godeungeo',
  '갈치': 'galchi',
  '삼치': 'samchi',
  '붕장어': 'bungjangeo',
  '부시리': 'busiri',
  '방어': 'bangeo',
  '도다리': 'dodari',
  '가자미': 'gazami',
  '노래미': 'noraemi',
  '쥐노래미': 'jwinoraemi',
  '무늬오징어': 'munuiojingeo',
  '갑오징어': 'gabojingeo',
  '한치': 'hanchi',
  '주꾸미': 'jukkumi',
  '문어': 'muneo',
  '배스': 'bass',
  '붕어': 'bungeo',
  '잉어': 'ingeo',
  '송어': 'songeo',
  '쏘가리': 'ssogari',
  '가물치': 'gamulchi',
  '메기': 'megi',
  '민물장어': 'minmuljangeo',
};

String? fishColorAsset(String species) {
  final key = kFishAssetKeys[species];
  return key == null ? null : 'assets/fish/color/$key-col.png';
}

String? fishSilhouetteAsset(String species) {
  final key = kFishAssetKeys[species];
  return key == null ? null : 'assets/fish/silhouette/$key-sil.png';
}
