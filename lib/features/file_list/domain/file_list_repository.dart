import 'models/file_summary.dart';

abstract interface class FileListRepository {
  Future<List<FileSummary>> listFiles(String savePath);
  Future<void> renameFile(String filePath, String newDisplayName);
  Future<void> copyFile(String filePath, String newDisplayName);
  Future<void> deleteFile(String filePath, {bool deletePhotos = false});
}
