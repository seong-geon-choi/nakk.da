import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/drive_backup_service.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../memo/data/md_serializer.dart';
import '../../../core/services/saf_service.dart';

final driveBackupServiceProvider = Provider((_) => DriveBackupService());

final backupProvider = AsyncNotifierProvider<BackupNotifier, BackupState>(
  BackupNotifier.new,
);

class BackupState {
  final bool enabled;
  final bool includeMedia;
  final String? accountEmail;
  final DateTime? lastSyncAt;
  final bool? lastSyncSuccess;

  const BackupState({
    this.enabled = false,
    this.includeMedia = false,
    this.accountEmail,
    this.lastSyncAt,
    this.lastSyncSuccess,
  });
}

class BackupNotifier extends AsyncNotifier<BackupState> {
  final _saf = SafService();

  @override
  Future<BackupState> build() async {
    final settings = await ref.watch(settingsProvider.future);
    final svc = ref.read(driveBackupServiceProvider);
    final isSignedIn = await svc.isSignedIn();
    return BackupState(
      enabled: settings.driveBackupEnabled,
      includeMedia: settings.driveBackupIncludeMedia,
      accountEmail: isSignedIn ? svc.accountEmail : null,
      lastSyncAt: settings.lastSyncAt,
      lastSyncSuccess: settings.lastSyncSuccess,
    );
  }

  Future<bool> enableBackup() async {
    try {
      final svc = ref.read(driveBackupServiceProvider);
      final email = await svc.signIn();
      if (email == null) return false;
      // settingsProvider 변경 시 backupProvider가 watch로 자동 rebuild 됨
      await ref.read(settingsProvider.notifier).updateDriveBackup(enabled: true);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> disableBackup() async {
    final svc = ref.read(driveBackupServiceProvider);
    await svc.signOut();
    await ref.read(settingsProvider.notifier).updateDriveBackup(
      enabled: false,
      clearLastSync: true,
    );
  }

  Future<void> setIncludeMedia(bool value) async {
    await ref.read(settingsProvider.notifier).updateDriveBackup(includeMedia: value);
  }

  /// 메모 저장/삭제 후 호출 — Wi-Fi 확인 후 md 파일 업로드
  Future<void> syncMdFile(DateTime date, String savePath) async {
    final settings = await ref.read(settingsProvider.future);
    if (!settings.driveBackupEnabled) return;
    final svc = ref.read(driveBackupServiceProvider);
    if (!await svc.isWifi()) return;
    try {
      final filename = _filename(date);
      final content = await _read(savePath, filename);
      if (content == null) return;
      await svc.syncMdFile(filename, content);
      await _updateSyncStatus(true);
    } catch (_) {
      await _updateSyncStatus(false);
    }
  }

  Future<void> syncMediaFile(String localPath) async {
    final settings = await ref.read(settingsProvider.future);
    if (!settings.driveBackupEnabled || !settings.driveBackupIncludeMedia) return;
    final svc = ref.read(driveBackupServiceProvider);
    if (!await svc.isWifi()) return;
    try {
      await svc.syncMediaFile(localPath);
    } catch (_) {}
  }

  Future<void> deleteMediaFile(String localPath) async {
    final settings = await ref.read(settingsProvider.future);
    if (!settings.driveBackupEnabled || !settings.driveBackupIncludeMedia) return;
    final svc = ref.read(driveBackupServiceProvider);
    try {
      await svc.deleteMediaFile(localPath);
    } catch (_) {}
  }

  /// 저장 폴더의 모든 .md 파일 (+ 옵션 시 사진/동영상)을 드라이브에 업로드
  Future<BackupAllResult> backupAll(String savePath) async {
    final settings = await ref.read(settingsProvider.future);
    final svc = ref.read(driveBackupServiceProvider);
    if (!await svc.isWifi()) {
      return const BackupAllResult(total: 0, succeeded: 0, skippedNoWifi: true);
    }

    // md 파일 백업
    final filenames = await _listMdFiles(savePath);
    int total = filenames.length;
    int succeeded = 0;
    for (final filename in filenames) {
      try {
        final content = await _read(savePath, filename);
        if (content == null) continue;
        await svc.syncMdFile(filename, content);
        succeeded++;
      } catch (_) {}
    }

    // 미디어 파일 백업
    if (settings.driveBackupIncludeMedia) {
      final mediaFiles = await _listMediaFiles(savePath);
      total += mediaFiles.length;
      for (final filename in mediaFiles) {
        try {
          final bytes = await _readMedia(savePath, filename);
          if (bytes == null || bytes.isEmpty) continue;
          final mimeType = filename.endsWith('.mp4') ? 'video/mp4' : 'image/jpeg';
          await svc.syncMediaBytes(filename, bytes, mimeType);
          succeeded++;
        } catch (_) {}
      }
    }

    await _updateSyncStatus(succeeded == total);
    return BackupAllResult(total: total, succeeded: succeeded);
  }

  Future<List<String>> _listMdFiles(String savePath) async {
    if (SafService.isSafUri(savePath)) return _saf.listMdFiles(savePath);
    final dir = Directory(savePath);
    if (!await dir.exists()) return [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'))
        .map((f) => f.path.split('/').last)
        .toList();
  }

  Future<List<String>> _listMediaFiles(String savePath) async {
    if (SafService.isSafUri(savePath)) return _saf.listPhotosFolder(savePath);
    final dir = Directory('$savePath/photos');
    if (!await dir.exists()) return [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.jpg') || f.path.endsWith('.mp4'))
        .map((f) => f.path.split('/').last)
        .toList();
  }

  Future<List<int>?> _readMedia(String savePath, String filename) async {
    if (SafService.isSafUri(savePath)) {
      final bytes = await _saf.readSafImage(savePath, 'photos/$filename');
      return bytes;
    }
    final file = File('$savePath/photos/$filename');
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  /// 드라이브 → 로컬 병합 복원
  Future<RestoreResult> restore(String savePath) async {
    final svc = ref.read(driveBackupServiceProvider);
    final files = await svc.listMdFiles();
    int restored = 0;
    for (final driveFile in files) {
      try {
        final driveContent = await svc.downloadMdFile(driveFile.id);
        if (driveContent == null) continue;
        final date = _parseDateFromFilename(driveFile.name);
        if (date == null) continue;
        final localContent = await _read(savePath, driveFile.name);
        final merged = localContent != null
            ? _mergeContent(localContent, driveContent, date)
            : driveContent;
        await _write(savePath, driveFile.name, merged, date);
        restored++;
      } catch (_) {}
    }
    return RestoreResult(filesRestored: restored);
  }

  String _mergeContent(String local, String remote, DateTime date) {
    final localBlocks = MdSerializer.parseBlocks(local, date);
    final remoteBlocks = MdSerializer.parseBlocks(remote, date);
    final mergedMap = <String, dynamic>{};
    for (final b in [...localBlocks, ...remoteBlocks]) {
      final key = _blockKey(b);
      if (!mergedMap.containsKey(key)) mergedMap[key] = b;
    }
    final sorted = mergedMap.values.toList()
      ..sort((a, b) => _blockTs(a).compareTo(_blockTs(b)));
    return MdSerializer.buildFullContent(date, sorted);
  }

  String _blockKey(dynamic b) => _blockTs(b).toIso8601String();
  DateTime _blockTs(dynamic b) {
    if (b is Map) return DateTime.now();
    try {
      return (b as dynamic).timestamp as DateTime;
    } catch (_) {
      return DateTime.now();
    }
  }

  Future<String?> _read(String savePath, String filename) async {
    if (SafService.isSafUri(savePath)) return _saf.readFile(savePath, filename);
    final file = File('$savePath/$filename');
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  Future<void> _write(String savePath, String filename, String content, DateTime date) async {
    if (SafService.isSafUri(savePath)) {
      await _saf.writeFile(savePath, filename, content);
    } else {
      final file = File('$savePath/$filename');
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
    }
  }

  Future<void> _updateSyncStatus(bool success) async {
    await ref.read(settingsProvider.notifier).updateDriveBackup(
      lastSyncAt: DateTime.now(),
      lastSyncSuccess: success,
    );
    ref.invalidateSelf();
  }

  String _filename(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}.md';

  DateTime? _parseDateFromFilename(String filename) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})\.md$').firstMatch(filename);
    if (m == null) return null;
    return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  }
}

class RestoreResult {
  final int filesRestored;
  const RestoreResult({required this.filesRestored});
}

class BackupAllResult {
  final int total;
  final int succeeded;
  final bool skippedNoWifi;
  const BackupAllResult({
    required this.total,
    required this.succeeded,
    this.skippedNoWifi = false,
  });
}
