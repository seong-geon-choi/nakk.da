import 'models/file_summary.dart';

abstract interface class FileListRepository {
  Future<List<FileSummary>> listFiles(String savePath);
  Future<void> renameFile(String filePath, String newDisplayName, String savePath);
  Future<void> copyFile(String filePath, String newDisplayName, String savePath);
  Future<void> deleteFile(String filePath, String savePath, {bool deletePhotos = false});
}
