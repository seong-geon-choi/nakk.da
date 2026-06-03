import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/memo_repository_impl.dart';
import '../domain/memo_repository.dart';
import '../domain/models/day_file.dart';
import '../domain/models/memo_entry.dart';
import '../../location/domain/models/location_status.dart';
import '../../settings/presentation/settings_provider.dart';
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
    await ref
        .read(memoRepositoryProvider)
        .appendEntry(DateTime.now(), entry, settings.savePath);
    ref.invalidateSelf();
  }

  Future<void> addLocationBlock(LocationStatus loc) async {
    final settings = await ref.read(settingsProvider.future);
    await ref
        .read(memoRepositoryProvider)
        .appendLocationBlock(DateTime.now(), loc, settings.savePath);
    ref.invalidateSelf();
  }

  Future<void> editBlock(int blockIndex, dynamic newBlock) async {
    final settings = await ref.read(settingsProvider.future);
    await ref
        .read(memoRepositoryProvider)
        .replaceBlock(DateTime.now(), blockIndex, newBlock, settings.savePath);
    ref.invalidateSelf();
  }

  Future<void> removeBlock(int blockIndex) async {
    final settings = await ref.read(settingsProvider.future);
    await ref
        .read(memoRepositoryProvider)
        .removeBlock(DateTime.now(), blockIndex, settings.savePath);
    ref.invalidateSelf();
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
  }

  Future<void> addLocationBlock(LocationStatus loc) async {
    final savePath = _savePath;
    if (savePath == null) return;
    await ref
        .read(memoRepositoryProvider)
        .appendLocationBlock(_date, loc, savePath);
    ref.invalidateSelf();
  }

  Future<void> editBlock(int blockIndex, dynamic newBlock) async {
    final savePath = _savePath;
    if (savePath == null) return;
    await ref
        .read(memoRepositoryProvider)
        .replaceBlock(_date, blockIndex, newBlock, savePath);
    ref.invalidateSelf();
  }

  Future<void> removeBlock(int blockIndex) async {
    final savePath = _savePath;
    if (savePath == null) return;
    await ref
        .read(memoRepositoryProvider)
        .removeBlock(_date, blockIndex, savePath);
    ref.invalidateSelf();
  }
}
