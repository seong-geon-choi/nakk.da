import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/file_list_repository_impl.dart';
import '../domain/file_list_repository.dart';
import '../domain/models/file_summary.dart';
import '../../settings/presentation/settings_provider.dart';

final fileListRepositoryProvider = Provider<FileListRepository>(
  (ref) => FileListRepositoryImpl(),
);

final fileListProvider =
    AsyncNotifierProvider<FileListNotifier, List<FileSummary>>(
  FileListNotifier.new,
);

class FileListNotifier extends AsyncNotifier<List<FileSummary>> {
  @override
  Future<List<FileSummary>> build() async {
    final settings = await ref.watch(settingsProvider.future);
    return ref
        .read(fileListRepositoryProvider)
        .listFiles(settings.savePath);
  }

  Future<void> rename(String filePath, String newName) async {
    await ref.read(fileListRepositoryProvider).renameFile(filePath, newName);
    ref.invalidateSelf();
  }

  Future<void> copy(String filePath, String newName) async {
    await ref.read(fileListRepositoryProvider).copyFile(filePath, newName);
    ref.invalidateSelf();
  }

  Future<void> delete(String filePath, {bool deletePhotos = false}) async {
    await ref
        .read(fileListRepositoryProvider)
        .deleteFile(filePath, deletePhotos: deletePhotos);
    ref.invalidateSelf();
  }
}
