import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math' show min;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/drive_backup_service.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../memo/data/md_serializer.dart';
import '../../../core/services/saf_service.dart';
import '../../../core/services/tracking_service.dart';

final driveBackupServiceProvider = Provider((_) => DriveBackupService());

final backupProvider = AsyncNotifierProvider<BackupNotifier, BackupState>(
  BackupNotifier.new,
);

/// 백업 진행 상태: null이면 백업 중 아님, (current, total)이면 진행 중
final backupProgressProvider = StateProvider<(int, int)?>((_) => null);

/// 복원 진행 상태: null이면 복원 중 아님, (current, total)이면 진행 중
final restoreProgressProvider = StateProvider<(int, int)?>((_) => null);


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

  /// 출퇴근/프리셋 설정 백업 디바운스 타이머(짧은 시간 다수 호출 시 1회만 업로드)
  Timer? _commuteBackupDebounce;

  @override
  Future<BackupState> build() async {
    ref.onDispose(() => _commuteBackupDebounce?.cancel());
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

  Future<({bool ok, String? error})> enableBackup() async {
    try {
      final svc = ref.read(driveBackupServiceProvider);
      final email = await svc.signIn();
      if (email == null) return (ok: false, error: '계정을 선택하지 않았습니다');
      await ref.read(settingsProvider.notifier).updateDriveBackup(enabled: true);
      return (ok: true, error: null);
    } catch (e) {
      return (ok: false, error: e.toString());
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

  /// 출퇴근/프리셋 설정 백업을 예약 — 3초 디바운스로 마지막 호출 1회만 업로드.
  /// (출조 저장 시 프리셋이 여러 개 한꺼번에 추가되는 상황의 중복 업로드 방지)
  Future<void> backupCommuteSettings() async {
    _commuteBackupDebounce?.cancel();
    _commuteBackupDebounce =
        Timer(const Duration(seconds: 3), () => unawaited(_uploadCommuteSettings()));
  }

  /// 실제 업로드 — 백업 켜짐 + Wi-Fi일 때만
  Future<void> _uploadCommuteSettings() async {
    final settings = await ref.read(settingsProvider.future);
    if (!settings.driveBackupEnabled) return;
    final svc = ref.read(driveBackupServiceProvider);
    if (!await svc.isWifi()) return;
    try {
      final json =
          jsonEncode(ref.read(settingsProvider.notifier).commuteBackupJson());
      await svc.uploadCommuteSettings(json);
    } catch (_) {}
  }

  /// 드라이브의 출퇴근 설정을 복원 — 적용되면 true
  Future<bool> restoreCommuteSettings() async {
    final svc = ref.read(driveBackupServiceProvider);
    try {
      final raw = await svc.downloadCommuteSettings();
      if (raw == null) return false;
      await ref
          .read(settingsProvider.notifier)
          .restoreCommuteFromJson(jsonDecode(raw) as Map<String, dynamic>);
      return true;
    } catch (_) {
      return false;
    }
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
    final progress = ref.read(backupProgressProvider.notifier);
    progress.state = (0, 0);
    try {
      final settings = await ref.read(settingsProvider.future);
      final svc = ref.read(driveBackupServiceProvider);
      if (!await svc.isWifi()) {
        return const BackupAllResult(total: 0, succeeded: 0, skippedNoWifi: true);
      }

      // 전체 파일 목록을 먼저 수집해서 total 확정
      final filenames = await _listMdFiles(savePath);

      // md 내용을 먼저 모두 읽어 외부 참조 사진(절대경로)을 수집
      final mdEntries = <({String filename, String content, int size})>[];
      final externalPhotos = <String, String>{}; // basename → 절대경로
      for (final filename in filenames) {
        final content = await _read(savePath, filename);
        if (content == null) continue;
        mdEntries.add((
          filename: filename,
          content: content,
          size: utf8.encode(content).length,
        ));
        if (settings.driveBackupIncludeMedia) {
          for (final p in externalPhotoPaths(content)) {
            externalPhotos.putIfAbsent(p.split('/').last, () => p);
          }
        }
      }

      final mediaFiles = settings.driveBackupIncludeMedia
          ? await _listMediaFiles(savePath)
          : <String>[];
      // 실제로 존재하는 외부 사진만 업로드 대상
      final externalList = <({String name, String path})>[
        if (settings.driveBackupIncludeMedia)
          for (final e in externalPhotos.entries)
            if (File(e.value).existsSync()) (name: e.key, path: e.value),
      ];

      final total = mdEntries.length + mediaFiles.length + externalList.length;
      int done = 0;
      progress.state = (done, total);

      // 로컬 매니페스트 + Drive 실제 파일 목록 (스킵 판단의 진실 원천)
      // 매니페스트는 최적화 캐시일 뿐, Drive에 실제로 존재하는지로 재업로드 결정
      // → 사용자가 Drive에서 직접 지운 파일도 다시 올림
      final manifest = await _loadManifest();
      final driveFiles = await svc.listMdFiles();
      final driveIdMap = {for (final f in driveFiles) f.name: f.id};
      final driveMediaSet = settings.driveBackupIncludeMedia
          ? (await svc.listMediaFiles()).map((f) => f.name).toSet()
          : <String>{};

      int succeeded = 0;
      int skipped = 0;

      // 업로드 대상 수집 (이미 읽어둔 내용 사용)
      final toUpload = <({String filename, String content, int size})>[];
      for (final item in mdEntries) {
        // 매니페스트 크기가 같아도 Drive에 실제로 있어야 스킵
        if (manifest[item.filename] == item.size &&
            driveIdMap.containsKey(item.filename)) {
          skipped++;
          progress.state = (++done, total);
        } else {
          toUpload.add(item);
        }
      }

      // 병렬 업로드 (4개씩 동시 실행, existingId 전달로 _findFile 생략)
      for (var i = 0; i < toUpload.length; i += 4) {
        final batch = toUpload.sublist(i, min(i + 4, toUpload.length));
        await Future.wait(batch.map((item) async {
          try {
            await svc.syncMdFile(item.filename, item.content,
                existingId: driveIdMap[item.filename]);
            manifest[item.filename] = item.size;
            succeeded++;
          } catch (_) {}
          progress.state = (++done, total);
        }));
      }

      // 미디어 파일 백업 — 매니페스트에 있고 Drive에도 실제로 있을 때만 스킵
      for (final filename in mediaFiles) {
        if (manifest.containsKey(filename) && driveMediaSet.contains(filename)) {
          skipped++;
          progress.state = (++done, total);
          continue;
        }
        try {
          final bytes = await _readMedia(savePath, filename);
          if (bytes != null && bytes.isNotEmpty) {
            final mimeType = filename.endsWith('.mp4') ? 'video/mp4' : 'image/jpeg';
            await svc.syncMediaBytes(filename, bytes, mimeType);
            manifest[filename] = bytes.length;
            succeeded++;
          }
        } catch (_) {}
        progress.state = (++done, total);
      }

      // 외부 참조 사진 백업 — basename 키로 업로드 (복원 시 _writeMedia가 photos/로 받음)
      for (final ext in externalList) {
        if (manifest.containsKey(ext.name) && driveMediaSet.contains(ext.name)) {
          skipped++;
          progress.state = (++done, total);
          continue;
        }
        try {
          final bytes = await File(ext.path).readAsBytes();
          if (bytes.isNotEmpty) {
            await svc.syncMediaBytes(ext.name, bytes, 'image/jpeg');
            manifest[ext.name] = bytes.length;
            succeeded++;
          }
        } catch (_) {}
        progress.state = (++done, total);
      }

      // 출퇴근 설정(지점 포함)도 함께 업로드
      try {
        await svc.uploadCommuteSettings(
            jsonEncode(ref.read(settingsProvider.notifier).commuteBackupJson()));
      } catch (_) {}

      await _saveManifest(manifest);
      await _updateSyncStatus(succeeded + skipped == total);
      return BackupAllResult(total: total, succeeded: succeeded, skipped: skipped);
    } finally {
      progress.state = null;
    }
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

  // .md 본문에서 외부 참조 사진(절대경로)만 추출.
  // photos/ 상대경로·content:// 동영상은 제외 (절대경로 '/'로 시작하는 것만).
  static final _photoRe = RegExp(r'!\[\]\((.+?)\)');
  static List<String> externalPhotoPaths(String content) {
    final out = <String>[];
    for (final m in _photoRe.allMatches(content)) {
      final p = m.group(1)!;
      if (p.startsWith('/')) out.add(p);
    }
    return out;
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
    final progress = ref.read(restoreProgressProvider.notifier);
    progress.state = (0, 0);
    try {
      final svc = ref.read(driveBackupServiceProvider);

      // 출퇴근 설정(지점 포함) 먼저 복원
      final commuteRestored = await restoreCommuteSettings();

      // 전체 복원 대상 파악 (total 확정)
      final mdFiles = await svc.listMdFiles();
      final localMediaSet = (await _listMediaFiles(savePath)).toSet();
      // 갤러리 원본(절대경로)이 이미 로컬에 있는 사진의 basename.
      // 원본이 있으면 photos/로 중복 다운로드하지 않는다(같은 기기 복원 시 사본 방지).
      final localOriginals = <String>{};
      for (final name in await _listMdFiles(savePath)) {
        final content = await _read(savePath, name);
        if (content == null) continue;
        for (final p in externalPhotoPaths(content)) {
          if (File(p).existsSync()) localOriginals.add(p.split('/').last);
        }
      }
      final driveMediaFiles = await svc.listMediaFiles();
      // total = md 전체 + Drive 미디어 전체 (이미 로컬에 있어도 progress에 포함)
      final total = mdFiles.length + driveMediaFiles.length;
      int done = 0;
      progress.state = (done, total);

      // .md 파일 복원 — 4개씩 병렬 처리
      // 매니페스트 size == 로컬 size면 마지막 백업 이후 변경 없음 → 다운로드 스킵
      final manifest = await _loadManifest();
      int restored = 0;
      for (var i = 0; i < mdFiles.length; i += 4) {
        final batch = mdFiles.sublist(i, min(i + 4, mdFiles.length));
        final counts = await Future.wait(batch.map((driveFile) async {
          try {
            final localContent = await _read(savePath, driveFile.name);
            if (localContent != null) {
              final localSize = utf8.encode(localContent).length;
              if (manifest[driveFile.name] == localSize) {
                return 0; // 백업 이후 변경 없음 — 스킵
              }
            }
            final driveContent = await svc.downloadMdFile(driveFile.id);
            if (driveContent == null) return 0;
            final date = _parseDateFromFilename(driveFile.name);
            if (date == null) return 0;
            final merged = localContent != null
                ? _mergeContent(localContent, driveContent, date)
                : driveContent;
            if (merged == localContent) return 0;
            await _write(savePath, driveFile.name, merged, date);
            return 1;
          } catch (_) {
            return 0;
          } finally {
            progress.state = (++done, total);
          }
        }));
        restored += counts.fold(0, (a, b) => a + b);
      }

      // 미디어 파일 복원 — 로컬에 없는 것만 다운로드, 있는 것은 progress만 업데이트
      int mediaRestored = 0;
      for (var i = 0; i < driveMediaFiles.length; i += 4) {
        final batch = driveMediaFiles.sublist(i, min(i + 4, driveMediaFiles.length));
        final counts = await Future.wait(batch.map((driveFile) async {
          // photos/에 이미 있거나, 갤러리 원본이 로컬에 있으면 다운로드 생략
          if (localMediaSet.contains(driveFile.name) ||
              localOriginals.contains(driveFile.name)) {
            progress.state = (++done, total);
            return 0;
          }
          try {
            final bytes = await svc.downloadMediaFile(driveFile.id);
            if (bytes == null || bytes.isEmpty) return 0;
            await _writeMedia(savePath, driveFile.name, bytes);
            return 1;
          } catch (_) {
            return 0;
          } finally {
            progress.state = (++done, total);
          }
        }));
        mediaRestored += counts.fold(0, (a, b) => a + b);
      }

      return RestoreResult(
        filesRestored: restored,
        mediaRestored: mediaRestored,
        mediaDriveTotal: driveMediaFiles.length,
        commuteRestored: commuteRestored,
      );
    } finally {
      progress.state = null;
    }
  }

  Future<void> _writeMedia(String savePath, String filename, List<int> bytes) async {
    if (SafService.isSafUri(savePath)) {
      await _saf.writePhotoBytes(savePath, filename, bytes);
    } else {
      final dir = Directory('$savePath/photos');
      if (!await dir.exists()) await dir.create(recursive: true);
      await File('$savePath/photos/$filename').writeAsBytes(bytes);
    }
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

    final localPoints = MdSerializer.parseTrackPoints(local);
    final remotePoints = MdSerializer.parseTrackPoints(remote);
    final pointMap = <String, TrackPoint>{};
    for (final p in [...localPoints, ...remotePoints]) {
      pointMap[p.timestamp.toIso8601String()] = p;
    }
    final mergedPoints = pointMap.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // 출조 정보는 로컬 우선, 없으면 원격 것을 보존
    final outing =
        MdSerializer.parseOuting(local) ?? MdSerializer.parseOuting(remote);
    return MdSerializer.buildFullContent(date, sorted, mergedPoints, outing);
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

  static const _manifestKey = 'backup_md_manifest';

  Future<Map<String, int>> _loadManifest() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_manifestKey);
    if (raw == null) return {};
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(k, (v as num).toInt()));
  }

  Future<void> _saveManifest(Map<String, int> manifest) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_manifestKey, jsonEncode(manifest));
  }

  Future<void> _updateSyncStatus(bool success) async {
    await ref.read(settingsProvider.notifier).updateDriveBackup(
      lastSyncAt: DateTime.now(),
      lastSyncSuccess: success,
    );
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
  final int mediaRestored;
  final int mediaDriveTotal;
  final bool commuteRestored;
  const RestoreResult({
    required this.filesRestored,
    this.mediaRestored = 0,
    this.mediaDriveTotal = 0,
    this.commuteRestored = false,
  });
}

class BackupAllResult {
  final int total;
  final int succeeded;
  final int skipped;
  final bool skippedNoWifi;
  const BackupAllResult({
    required this.total,
    required this.succeeded,
    this.skipped = 0,
    this.skippedNoWifi = false,
  });
}
