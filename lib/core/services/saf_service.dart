import 'package:flutter/services.dart';

class SafService {
  static const _channel = MethodChannel('com.nakkda.nakkda/saf');

  static bool isSafUri(String? path) => path?.startsWith('content://') == true;

  Future<({String uri, String displayPath})?> pickFolder() async {
    final result = await _channel.invokeMapMethod<String, String>('pickFolder');
    if (result == null) return null;
    final uri = result['uri'];
    final displayPath = result['displayPath'];
    if (uri == null || displayPath == null) return null;
    return (uri: uri, displayPath: displayPath);
  }

  Future<String?> readFile(String folderUri, String filename) =>
      _channel.invokeMethod<String>('readTextFile', {'uri': folderUri, 'filename': filename});

  Future<void> writeFile(String folderUri, String filename, String content) =>
      _channel.invokeMethod('writeTextFile', {'uri': folderUri, 'filename': filename, 'content': content});

  Future<void> appendFile(String folderUri, String filename, String content) =>
      _channel.invokeMethod('appendTextFile', {'uri': folderUri, 'filename': filename, 'content': content});

  Future<bool> fileExists(String folderUri, String filename) async =>
      await _channel.invokeMethod<bool>('fileExists', {'uri': folderUri, 'filename': filename}) ?? false;

  Future<List<String>> listMdFiles(String folderUri) async {
    final result = await _channel.invokeListMethod<String>('listMdFiles', {'uri': folderUri});
    return result ?? [];
  }

  Future<void> ensureFolder(String folderUri) =>
      _channel.invokeMethod('ensureFolder', {'uri': folderUri});

  Future<void> deleteFile(String folderUri, String filename) =>
      _channel.invokeMethod('deleteFile', {'uri': folderUri, 'filename': filename});

  Future<void> renameFile(String folderUri, String oldFilename, String newFilename) =>
      _channel.invokeMethod('renameFile', {
        'uri': folderUri, 'oldFilename': oldFilename, 'newFilename': newFilename,
      });

  Future<void> copyFile(String folderUri, String srcFilename, String dstFilename) =>
      _channel.invokeMethod('copyFile', {
        'uri': folderUri, 'srcFilename': srcFilename, 'dstFilename': dstFilename,
      });

  Future<String> getDisplayPath(String folderUri) async =>
      await _channel.invokeMethod<String>('getDisplayPath', {'uri': folderUri}) ?? folderUri;
}
