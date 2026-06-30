import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

class DriveBackupService {
  static const _folderName = '낚다(NAKKDA)';

  final _signIn = GoogleSignIn(scopes: [drive.DriveApi.driveFileScope]);

  String? _folderId;
  String? _photosFolderId;
  drive.DriveApi? _api;

  Future<bool> isSignedIn() => _signIn.isSignedIn();
  String? get accountEmail => _signIn.currentUser?.email;

  Future<String?> signIn() async {
    final account = await _signIn.signIn();
    return account?.email;
  }

  Future<void> signOut() async {
    _api = null;
    _folderId = null;
    _photosFolderId = null;
    await _signIn.signOut();
  }

  Future<bool> isWifi() async {
    final result = await Connectivity().checkConnectivity();
    return result.contains(ConnectivityResult.wifi);
  }

  Future<drive.DriveApi?> _getApi() async {
    if (_api != null) return _api;
    var account = _signIn.currentUser;
    account ??= await _signIn.signInSilently();
    if (account == null) return null;
    final headers = await account.authHeaders;
    _api = drive.DriveApi(_AuthClient(headers));
    return _api;
  }

  Future<String> _getOrCreateFolder(drive.DriveApi api) async {
    if (_folderId != null) return _folderId!;
    final list = await api.files.list(
      q: "name='$_folderName' and mimeType='application/vnd.google-apps.folder' and trashed=false",
      spaces: 'drive',
      $fields: 'files(id)',
    );
    if (list.files?.isNotEmpty == true) {
      _folderId = list.files!.first.id!;
      return _folderId!;
    }
    final created = await api.files.create(
      drive.File()
        ..name = _folderName
        ..mimeType = 'application/vnd.google-apps.folder',
      $fields: 'id',
    );
    _folderId = created.id!;
    return _folderId!;
  }

  Future<String> _getOrCreatePhotosFolder(drive.DriveApi api, String parentId) async {
    if (_photosFolderId != null) return _photosFolderId!;
    final list = await api.files.list(
      q: "name='photos' and mimeType='application/vnd.google-apps.folder' and '$parentId' in parents and trashed=false",
      spaces: 'drive',
      $fields: 'files(id)',
    );
    if (list.files?.isNotEmpty == true) {
      _photosFolderId = list.files!.first.id!;
      return _photosFolderId!;
    }
    final created = await api.files.create(
      drive.File()
        ..name = 'photos'
        ..parents = [parentId]
        ..mimeType = 'application/vnd.google-apps.folder',
      $fields: 'id',
    );
    _photosFolderId = created.id!;
    return _photosFolderId!;
  }

  Future<String?> _findFile(drive.DriveApi api, String name, String parentId) async {
    final list = await api.files.list(
      q: "name='$name' and '$parentId' in parents and trashed=false",
      spaces: 'drive',
      $fields: 'files(id)',
    );
    return list.files?.firstOrNull?.id;
  }

  Future<void> syncMdFile(String filename, String content, {String? existingId}) async {
    final api = await _getApi();
    if (api == null) return;
    final folderId = await _getOrCreateFolder(api);
    final fileId = existingId ?? await _findFile(api, filename, folderId);
    final bytes = utf8.encode(content);
    final media = drive.Media(
      Stream.value(bytes),
      bytes.length,
      contentType: 'text/markdown',
    );
    if (fileId != null) {
      await api.files.update(drive.File(), fileId, uploadMedia: media);
    } else {
      await api.files.create(
        drive.File()
          ..name = filename
          ..parents = [folderId],
        uploadMedia: media,
        $fields: 'id',
      );
    }
  }

  static const _commuteFile = 'commute_settings.json';

  /// 출퇴근 설정(JSON)을 백업 폴더에 업로드(있으면 갱신).
  Future<void> uploadCommuteSettings(String json) async {
    final api = await _getApi();
    if (api == null) return;
    final folderId = await _getOrCreateFolder(api);
    final fileId = await _findFile(api, _commuteFile, folderId);
    final bytes = utf8.encode(json);
    final media = drive.Media(
      Stream.value(bytes),
      bytes.length,
      contentType: 'application/json',
    );
    if (fileId != null) {
      await api.files.update(drive.File(), fileId, uploadMedia: media);
    } else {
      await api.files.create(
        drive.File()
          ..name = _commuteFile
          ..parents = [folderId],
        uploadMedia: media,
        $fields: 'id',
      );
    }
  }

  /// 백업 폴더의 출퇴근 설정(JSON) 다운로드. 없으면 null.
  Future<String?> downloadCommuteSettings() async {
    final api = await _getApi();
    if (api == null) return null;
    final folderId = await _getOrCreateFolder(api);
    final fileId = await _findFile(api, _commuteFile, folderId);
    if (fileId == null) return null;
    final media = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final chunks = <int>[];
    await for (final chunk in media.stream) {
      chunks.addAll(chunk);
    }
    return utf8.decode(chunks);
  }

  Future<void> syncMediaFile(String localPath) async {
    final file = File(localPath);
    if (!await file.exists()) return;
    final bytes = await file.readAsBytes();
    final filename = localPath.split('/').last;
    final mimeType = localPath.endsWith('.mp4') ? 'video/mp4' : 'image/jpeg';
    await syncMediaBytes(filename, bytes, mimeType);
  }

  Future<void> syncMediaBytes(String filename, List<int> bytes, String mimeType) async {
    final api = await _getApi();
    if (api == null) return;
    final folderId = await _getOrCreateFolder(api);
    final photosFolderId = await _getOrCreatePhotosFolder(api, folderId);
    if (await _findFile(api, filename, photosFolderId) != null) return; // 이미 있으면 skip
    await api.files.create(
      drive.File()
        ..name = filename
        ..parents = [photosFolderId],
      uploadMedia: drive.Media(Stream.value(bytes), bytes.length, contentType: mimeType),
      $fields: 'id',
    );
  }

  Future<void> deleteMediaFile(String localPath) async {
    final filename = localPath.split('/').last;
    final api = await _getApi();
    if (api == null) return;
    final folderId = await _getOrCreateFolder(api);
    final photosFolderId = await _getOrCreatePhotosFolder(api, folderId);
    final fileId = await _findFile(api, filename, photosFolderId);
    if (fileId == null) return;
    await api.files.delete(fileId);
  }

  Future<List<DriveFileInfo>> listMdFiles() async {
    final api = await _getApi();
    if (api == null) return [];
    final folderId = await _getOrCreateFolder(api);
    final list = await api.files.list(
      q: "name contains '.md' and '$folderId' in parents and trashed=false",
      spaces: 'drive',
      $fields: 'files(id,name,modifiedTime,size)',
      orderBy: 'name desc',
    );
    return (list.files ?? [])
        .map((f) => DriveFileInfo(
              id: f.id!,
              name: f.name!,
              modifiedTime: f.modifiedTime,
              size: f.size != null ? int.tryParse(f.size!) : null,
            ))
        .toList();
  }

  Future<String?> downloadMdFile(String fileId) async {
    final api = await _getApi();
    if (api == null) return null;
    final media = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final chunks = <int>[];
    await for (final chunk in media.stream) {
      chunks.addAll(chunk);
    }
    return utf8.decode(chunks);
  }

  Future<List<DriveFileInfo>> listMediaFiles() async {
    final api = await _getApi();
    if (api == null) return [];
    final folderId = await _getOrCreateFolder(api);
    final photosFolderId = await _getOrCreatePhotosFolder(api, folderId);
    final list = await api.files.list(
      q: "'$photosFolderId' in parents and trashed=false",
      spaces: 'drive',
      $fields: 'files(id,name)',
    );
    return (list.files ?? [])
        .map((f) => DriveFileInfo(id: f.id!, name: f.name!))
        .toList();
  }

  Future<List<int>?> downloadMediaFile(String fileId) async {
    final api = await _getApi();
    if (api == null) return null;
    final media = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final chunks = <int>[];
    await for (final chunk in media.stream) {
      chunks.addAll(chunk);
    }
    return chunks;
  }
}

class DriveFileInfo {
  final String id;
  final String name;
  final DateTime? modifiedTime;
  final int? size;
  const DriveFileInfo({required this.id, required this.name, this.modifiedTime, this.size});
}

class _AuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final _inner = http.Client();
  _AuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request..headers.addAll(_headers));
}
