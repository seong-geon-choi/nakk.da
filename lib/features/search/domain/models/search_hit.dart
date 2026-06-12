import '../../../memo/domain/models/memo_entry.dart';

/// 검색 결과 한 건 — 특정 날짜 파일의 메모 엔트리 하나.
class SearchHit {
  final DateTime date;
  final String filePath;
  final String displayName;
  final MemoEntry entry;
  final String? address; // 해당 날짜 파일의 대표 장소(주소)

  const SearchHit({
    required this.date,
    required this.filePath,
    required this.displayName,
    required this.entry,
    this.address,
  });
}
