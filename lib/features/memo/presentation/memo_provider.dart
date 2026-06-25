import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/memo_repository_impl.dart';
import '../domain/memo_repository.dart';
import '../domain/models/day_file.dart';
import '../domain/models/memo_entry.dart';
import '../../location/domain/models/location_status.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../backup/presentation/backup_provider.dart';
import '../../file_list/presentation/file_list_provider.dart';
import '../../../core/utils/file_name_parser.dart';

final memoRepositoryProvider = Provider<MemoRepository>(
  (ref) => MemoRepositoryImpl(),
);

/// 오늘 날짜의 메모 파일 경로(savePath + yyyy-MM-dd.md).
/// 통합 화면(DayMemoScreen)·지도·편집기에서 '오늘'을 dayFileProvider로 일원화하는 데 사용.
String todayMemoFilePath(String savePath) {
  final d = DateTime.now();
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$savePath/${d.year}-$m-$day.md';
}

// ── 특정 파일을 날짜로 읽고 쓰는 family provider ───────────────

final dayFileProvider =
    AsyncNotifierProviderFamily<DayFileNotifier, DayFile?, String>(
  DayFileNotifier.new,
);

class DayFileNotifier extends FamilyAsyncNotifier<DayFile?, String> {
  String? _savePath;

  DateTime get _date {
    final fileName = arg.replaceAll('\\', '/').split('/').last;
    return FileNameParser.parseDate(fileName) ?? DateTime.now();
  }

  @override
  Future<DayFile?> build(String arg) async {
    // savePath만 구독 — 무관한 설정 변경 시 재로딩(깜빡임) 방지
    final savePath =
        await ref.watch(settingsProvider.selectAsync((s) => s.savePath));
    _savePath = savePath;
    return ref.read(memoRepositoryProvider).loadDayFile(_date, savePath);
  }

  Future<void> addEntry(MemoEntry entry) async {
    final savePath = _savePath;
    if (savePath == null) return;
    await ref.read(memoRepositoryProvider).appendEntry(_date, entry, savePath);
    ref.invalidateSelf();
    ref.invalidate(fileListProvider); // 목록의 주소·메모수 즉시 갱신(변경 파일만 재읽기)
    unawaited(ref.read(backupProvider.notifier).syncMdFile(_date, savePath));
    if (entry.photoPath != null) {
      unawaited(ref.read(backupProvider.notifier).syncMediaFile(entry.photoPath!));
    }
    if (entry.videoPath != null) {
      unawaited(ref.read(backupProvider.notifier).syncMediaFile(entry.videoPath!));
    }
  }

  Future<void> addLocationBlock(LocationStatus loc) async {
    final savePath = _savePath;
    if (savePath == null) return;
    await ref.read(memoRepositoryProvider).appendLocationBlock(_date, loc, savePath);
    ref.invalidateSelf();
    ref.invalidate(fileListProvider); // 목록의 주소·메모수 즉시 갱신(변경 파일만 재읽기)
    unawaited(ref.read(backupProvider.notifier).syncMdFile(_date, savePath));
  }

  Future<void> editBlock(int blockIndex, dynamic newBlock) async {
    final savePath = _savePath;
    if (savePath == null) return;
    await ref.read(memoRepositoryProvider).replaceBlock(_date, blockIndex, newBlock, savePath);
    ref.invalidateSelf();
    ref.invalidate(fileListProvider); // 목록의 주소·메모수 즉시 갱신(변경 파일만 재읽기)
    unawaited(ref.read(backupProvider.notifier).syncMdFile(_date, savePath));
  }

  Future<void> removeBlock(int blockIndex) async {
    final savePath = _savePath;
    if (savePath == null) return;
    final dayFile = state.valueOrNull;
    final block = (dayFile != null && blockIndex < dayFile.blocks.length)
        ? dayFile.blocks[blockIndex]
        : null;
    await ref.read(memoRepositoryProvider).removeBlock(_date, blockIndex, savePath);
    ref.invalidateSelf();
    ref.invalidate(fileListProvider); // 목록의 주소·메모수 즉시 갱신(변경 파일만 재읽기)
    unawaited(ref.read(backupProvider.notifier).syncMdFile(_date, savePath));
    if (block is MemoEntry) {
      if (block.photoPath != null) {
        unawaited(ref.read(backupProvider.notifier).deleteMediaFile(block.photoPath!));
      }
      if (block.videoPath != null) {
        unawaited(ref.read(backupProvider.notifier).deleteMediaFile(block.videoPath!));
      }
    }
  }
}
