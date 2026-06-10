import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/memo_repository_impl.dart';
import '../domain/memo_repository.dart';
import '../domain/models/day_file.dart';
import '../domain/models/memo_entry.dart';
import '../../location/domain/models/location_status.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../backup/presentation/backup_provider.dart';
import '../../../core/utils/file_name_parser.dart';

final memoRepositoryProvider = Provider<MemoRepository>(
  (ref) => MemoRepositoryImpl(),
);

final todayFileProvider = AsyncNotifierProvider<TodayFileNotifier, DayFile?>(
  TodayFileNotifier.new,
);

class TodayFileNotifier extends AsyncNotifier<DayFile?> {
  @override
  Future<DayFile?> build() async {
    final settings = await ref.watch(settingsProvider.future);
    return ref
        .read(memoRepositoryProvider)
        .loadDayFile(DateTime.now(), settings.savePath);
  }

  Future<void> addEntry(MemoEntry entry) async {
    final settings = await ref.read(settingsProvider.future);
    final date = DateTime.now();
    await ref.read(memoRepositoryProvider).appendEntry(date, entry, settings.savePath);
    ref.invalidateSelf();
    unawaited(ref.read(backupProvider.notifier).syncMdFile(date, settings.savePath));
    if (entry.photoPath != null) {
      unawaited(ref.read(backupProvider.notifier).syncMediaFile(entry.photoPath!));
    }
    if (entry.videoPath != null) {
      unawaited(ref.read(backupProvider.notifier).syncMediaFile(entry.videoPath!));
    }
  }

  Future<void> addLocationBlock(LocationStatus loc) async {
    final settings = await ref.read(settingsProvider.future);
    final date = DateTime.now();
    await ref.read(memoRepositoryProvider).appendLocationBlock(date, loc, settings.savePath);
    ref.invalidateSelf();
    unawaited(ref.read(backupProvider.notifier).syncMdFile(date, settings.savePath));
  }

  Future<void> editBlock(int blockIndex, dynamic newBlock) async {
    final settings = await ref.read(settingsProvider.future);
    final date = DateTime.now();
    await ref.read(memoRepositoryProvider).replaceBlock(date, blockIndex, newBlock, settings.savePath);
    ref.invalidateSelf();
    unawaited(ref.read(backupProvider.notifier).syncMdFile(date, settings.savePath));
  }

  Future<void> removeBlock(int blockIndex) async {
    final settings = await ref.read(settingsProvider.future);
    final date = DateTime.now();
    final dayFile = state.valueOrNull;
    final block = (dayFile != null && blockIndex < dayFile.blocks.length)
        ? dayFile.blocks[blockIndex]
        : null;
    await ref.read(memoRepositoryProvider).removeBlock(date, blockIndex, settings.savePath);
    ref.invalidateSelf();
    unawaited(ref.read(backupProvider.notifier).syncMdFile(date, settings.savePath));
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
    final settings = await ref.watch(settingsProvider.future);
    _savePath = settings.savePath;
    return ref.read(memoRepositoryProvider).loadDayFile(_date, _savePath!);
  }

  Future<void> addEntry(MemoEntry entry) async {
    final savePath = _savePath;
    if (savePath == null) return;
    await ref.read(memoRepositoryProvider).appendEntry(_date, entry, savePath);
    ref.invalidateSelf();
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
    unawaited(ref.read(backupProvider.notifier).syncMdFile(_date, savePath));
  }

  Future<void> editBlock(int blockIndex, dynamic newBlock) async {
    final savePath = _savePath;
    if (savePath == null) return;
    await ref.read(memoRepositoryProvider).replaceBlock(_date, blockIndex, newBlock, savePath);
    ref.invalidateSelf();
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
