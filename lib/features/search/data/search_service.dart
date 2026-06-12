import 'dart:io';
import '../../../core/services/saf_service.dart';
import '../../../core/utils/file_name_parser.dart';
import '../../memo/data/md_serializer.dart';
import '../../memo/domain/models/memo_entry.dart';
import '../domain/models/search_hit.dart';

/// 저장 폴더의 모든 .md 파일을 파싱해 메모 엔트리 목록(SearchHit)으로 평탄화.
class SearchService {
  final _saf = SafService();

  Future<List<SearchHit>> loadAllHits(String savePath) async {
    if (savePath.isEmpty) return [];

    final files = <({DateTime date, String filePath, String name, String content})>[];
    if (SafService.isSafUri(savePath)) {
      final names = await _saf.listMdFiles(savePath);
      for (final name in names) {
        final date = FileNameParser.parseDate(name);
        if (date == null) continue;
        final content = await _saf.readFile(savePath, name) ?? '';
        files.add((
          date: date,
          filePath: '$savePath/$name',
          name: name.replaceAll('.md', ''),
          content: content,
        ));
      }
    } else {
      final dir = Directory(savePath);
      if (!await dir.exists()) return [];
      await for (final e in dir.list()) {
        if (e is! File || !e.path.endsWith('.md')) continue;
        final fname = e.uri.pathSegments.last;
        final date = FileNameParser.parseDate(fname);
        if (date == null) continue;
        files.add((
          date: date,
          filePath: e.path,
          name: fname.replaceAll('.md', ''),
          content: await e.readAsString(),
        ));
      }
    }

    final hits = <SearchHit>[];
    for (final f in files) {
      final address = _firstAddress(f.content);
      for (final block in MdSerializer.parseBlocks(f.content, f.date)) {
        if (block is MemoEntry) {
          hits.add(SearchHit(
            date: f.date,
            filePath: f.filePath,
            displayName: f.name,
            entry: block,
            address: address,
          ));
        }
      }
    }
    // 최신 날짜 우선, 같은 날짜 내 시간 오름차순
    hits.sort((a, b) {
      final c = b.date.compareTo(a.date);
      return c != 0 ? c : a.entry.timestamp.compareTo(b.entry.timestamp);
    });
    return hits;
  }

  String? _firstAddress(String content) {
    final m = RegExp(r'- 📍 (.+)').firstMatch(content);
    final raw = m?.group(1)?.trim();
    // GPS 좌표만 있는 경우는 주소로 취급하지 않음
    if (raw == null || RegExp(r'^-?\d+\.\d+,\s*-?\d+\.\d+$').hasMatch(raw)) {
      return null;
    }
    return raw;
  }
}
