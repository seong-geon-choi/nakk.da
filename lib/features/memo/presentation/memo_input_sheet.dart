import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../domain/models/memo_entry.dart';
import 'memo_provider.dart';
import 'voice_input_provider.dart';
import '../../../features/location/presentation/location_provider.dart';
import '../../../features/permission/presentation/permission_provider.dart';
import '../../../features/settings/presentation/settings_provider.dart';
import '../../../features/photo/domain/photo_service.dart';
import '../../../features/photo/presentation/camera_ruler_screen.dart';
import '../../../core/utils/media_scanner.dart';
import '../../../core/utils/watermark.dart';
import '../../../core/services/ar_service.dart';
import '../../../core/utils/exif_utils.dart';
import '../../../core/services/saf_service.dart';
import '../../../core/widgets/saf_image.dart';
import '../../../core/widgets/video_player_widget.dart';
import '../../../core/screens/gallery_picker_screen.dart';

class MemoInputSheet extends ConsumerStatefulWidget {
  final bool startWithVoice;
  final MemoEntry? existingEntry;
  final int? blockIndex;
  final String? initialPhotoPath;
  final String? initialVideoPath;
  final double? initialFishLength;
  final String? initialText;
  final double? initialLatitude;
  final double? initialLongitude;
  final DateTime? initialTimestamp;
  final Future<void> Function(int blockIndex, MemoEntry updated)? onEditSave;
  final Future<void> Function(MemoEntry entry)? onAddSave;

  const MemoInputSheet({
    super.key,
    this.startWithVoice = false,
    this.existingEntry,
    this.blockIndex,
    this.initialPhotoPath,
    this.initialVideoPath,
    this.initialFishLength,
    this.initialText,
    this.initialLatitude,
    this.initialLongitude,
    this.initialTimestamp,
    this.onEditSave,
    this.onAddSave,
  });

  static Future<void> show(
    BuildContext context, {
    bool voiceMode = false,
    MemoEntry? existingEntry,
    int? blockIndex,
    String? initialPhotoPath,
    String? initialVideoPath,
    double? initialFishLength,
    String? initialText,
    double? initialLatitude,
    double? initialLongitude,
    DateTime? initialTimestamp,
    Future<void> Function(int, MemoEntry)? onEditSave,
    Future<void> Function(MemoEntry)? onAddSave,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxWidth: math.min(MediaQuery.of(context).size.width, 600),
      ),
      builder: (_) => MemoInputSheet(
        startWithVoice: voiceMode,
        existingEntry: existingEntry,
        blockIndex: blockIndex,
        initialPhotoPath: initialPhotoPath,
        initialVideoPath: initialVideoPath,
        initialFishLength: initialFishLength,
        initialText: initialText,
        initialLatitude: initialLatitude,
        initialLongitude: initialLongitude,
        initialTimestamp: initialTimestamp,
        onEditSave: onEditSave,
        onAddSave: onAddSave,
      ),
    );
  }

  /// 소스 선택 → 사진/동영상 촬영/선택까지 처리.
  static Future<({String path, bool isVideo, double? length, ({double lat, double lng})? gps, DateTime? timestamp})?> pickMedia(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final source = await showModalBottomSheet<PhotoSource>(
      context: context,
      constraints: BoxConstraints(
        maxWidth: math.min(MediaQuery.of(context).size.width, 600),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.view_in_ar_outlined),
              title: const Text('AR 길이 측정'),
              onTap: () => Navigator.of(sheetCtx).pop(PhotoSource.arCamera),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('카메라'),
              subtitle: const Text('사진/동영상 스와이프로 선택'),
              onTap: () => Navigator.of(sheetCtx).pop(PhotoSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('갤러리'),
              onTap: () => Navigator.of(sheetCtx).pop(PhotoSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return null;

    final settings = ref.read(settingsProvider).valueOrNull;
    final relPath = _mediaRelPath(settings?.photoSavePath ?? 'DCIM/nakkda');
    String? path;
    bool isVideo = false;
    double? length;
    ({double lat, double lng})? gps;
    String? exifSourcePath;

    if (source == PhotoSource.arCamera) {
      final wmSettings = settings?.watermark;
      final arResult = await launchArMeasure(
        watermarkEnabled: wmSettings?.enabled ?? false,
        watermarkSettings: wmSettings,
      );
      if (arResult == null || !context.mounted) return null;
      final rawPath = (arResult.applyWatermark && wmSettings != null)
          ? await applyWatermark(arResult.path, wmSettings.copyWith(enabled: true))
          : arResult.path;
      exifSourcePath = rawPath;
      path = await saveToGallery(rawPath, relativePath: relPath);
      length = arResult.distanceCm;
    } else if (source == PhotoSource.camera) {
      final camResult = await Navigator.of(context)
          .push<({String path, bool isVideo})>(
        MaterialPageRoute(builder: (_) => const CameraRulerScreen()),
      );
      if (camResult == null || !context.mounted) return null;

      if (camResult.isVideo) {
        // 카메라 동영상: _saveVideo()가 이미 앱 스토리지에 저장했으므로 경로 그대로 사용
        isVideo = true;
        path = camResult.path;
        // GPS는 현재 위치로 폴백
        final loc = ref.read(locationProvider).valueOrNull;
        if (loc?.latitude != null) {
          gps = (lat: loc!.latitude!, lng: loc.longitude!);
        } else {
          final cached = ref.read(locationProvider.notifier).cached;
          if (cached?.latitude != null) {
            gps = (lat: cached!.latitude!, lng: cached.longitude!);
          }
        }
      } else {
        // 카메라 사진: 기존 플로우
        exifSourcePath = camResult.path;
        path = await saveToGallery(camResult.path, relativePath: relPath);
      }
    } else {
      // gallery: 커스텀 갤러리 화면 (전체/사진/동영상 탭)
      final picked = await Navigator.of(context).push<({String path, bool isVideo})>(
        MaterialPageRoute(builder: (_) => const GalleryPickerScreen()),
      );
      if (picked == null || !context.mounted) return null;
      isVideo = picked.isVideo;
      if (isVideo) {
        final savedPath = await MemoInputSheet.copyGalleryVideo(picked.path, settings?.savePath ?? '');
        if (savedPath == null) return null;
        path = savedPath;
      } else {
        exifSourcePath = picked.path;
        final savePath = settings?.savePath ?? '';
        path = await MemoInputSheet.copyGalleryPhoto(picked.path, savePath);
      }
    }

    // EXIF GPS·촬영 시간 (사진 전용)
    DateTime? timestamp;
    if (exifSourcePath != null) {
      gps ??= await readExifGps(exifSourcePath);
      timestamp = await readExifTimestamp(exifSourcePath);
    }

    // 카메라/AR 소스 GPS 폴백
    if (!isVideo && gps == null &&
        (source == PhotoSource.camera || source == PhotoSource.arCamera)) {
      final loc = ref.read(locationProvider).valueOrNull;
      if (loc?.latitude != null) {
        gps = (lat: loc!.latitude!, lng: loc.longitude!);
      } else {
        final cached = ref.read(locationProvider.notifier).cached;
        if (cached?.latitude != null) {
          gps = (lat: cached!.latitude!, lng: cached.longitude!);
        }
      }
    }

    if (path == null) return null;
    return (path: path, isVideo: isVideo, length: length, gps: gps, timestamp: timestamp);
  }

  /// 갤러리 사진을 savePath의 photos/ 서브폴더에 복사, 상대 경로 반환
  static Future<String?> copyGalleryPhoto(String cachePath, String savePath, {String? filenameOverride}) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ext = cachePath.contains('.') ? cachePath.split('.').last.toLowerCase() : 'jpg';
    final filename = filenameOverride ?? 'gallery_$ts.$ext';
    if (SafService.isSafUri(savePath)) {
      try {
        await SafService().copyFileToSafFolder(cachePath, savePath, filename);
        return 'photos/$filename';
      } catch (_) { return null; }
    } else if (savePath.isNotEmpty) {
      try {
        final photosDir = Directory('$savePath/photos');
        await photosDir.create(recursive: true);
        await File(cachePath).copy('${photosDir.path}/$filename');
        return 'photos/$filename';
      } catch (_) { return null; }
    }
    return null;
  }

  /// 갤러리 동영상을 savePath/videos/에 복사, 상대 경로 반환 (SAF/미설정 시 절대 경로)
  static Future<String?> copyGalleryVideo(String tempPath, String savePath) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ext = tempPath.contains('.') ? tempPath.split('.').last.toLowerCase() : 'mp4';
    final filename = 'gallery_video_$ts.$ext';
    if (savePath.isNotEmpty && !savePath.startsWith('content://')) {
      try {
        final videosDir = Directory('$savePath/videos');
        await videosDir.create(recursive: true);
        await File(tempPath).copy('$savePath/videos/$filename');
        return 'videos/$filename';
      } catch (_) { return null; }
    } else {
      try {
        final dir = await getExternalStorageDirectory();
        if (dir == null) return null;
        final videosDir = Directory('${dir.path}/videos');
        await videosDir.create(recursive: true);
        await File(tempPath).copy('${videosDir.path}/$filename');
        return '${videosDir.path}/$filename';
      } catch (_) { return null; }
    }
  }

  static String _mediaRelPath(String photoSavePath) {
    final lower = photoSavePath.toLowerCase();
    for (final marker in ['dcim/', 'pictures/', 'downloads/']) {
      final idx = lower.indexOf(marker);
      if (idx >= 0) return photoSavePath.substring(idx);
    }
    return 'DCIM/nakkda';
  }

  @override
  ConsumerState<MemoInputSheet> createState() => _MemoInputSheetState();
}

class _MemoInputSheetState extends ConsumerState<MemoInputSheet> {
  final _textCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _fishLengthCtrl = TextEditingController();
  late DateTime _timestamp;
  String? _photoPath;
  String? _videoPath;
  bool _saving = false;
  bool _gpsUpdating = false;

  bool get _isEditMode => widget.blockIndex != null && widget.existingEntry != null;

  @override
  void initState() {
    super.initState();
    final entry = widget.existingEntry;
    if (entry != null) {
      _timestamp = entry.timestamp;
      _photoPath = entry.photoPath;
      _videoPath = entry.videoPath;
      _textCtrl.text = entry.text ?? '';
      if (entry.latitude != null) _latCtrl.text = entry.latitude!.toStringAsFixed(4);
      if (entry.longitude != null) _lngCtrl.text = entry.longitude!.toStringAsFixed(4);
      if (entry.fishLength != null) _fishLengthCtrl.text = entry.fishLength!.toStringAsFixed(1);
    } else {
      _timestamp = widget.initialTimestamp ?? DateTime.now();
      if (widget.initialText != null) _textCtrl.text = widget.initialText!;
      _photoPath = widget.initialPhotoPath;
      _videoPath = widget.initialVideoPath;
      if (widget.initialFishLength != null) {
        _fishLengthCtrl.text = widget.initialFishLength!.toStringAsFixed(1);
      }
      if (widget.initialLatitude != null) {
        _latCtrl.text = widget.initialLatitude!.toStringAsFixed(4);
        _lngCtrl.text = widget.initialLongitude!.toStringAsFixed(4);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoFillGps());
    }
    if (widget.startWithVoice) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startVoice());
    }
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _fishLengthCtrl.dispose();
    super.dispose();
  }

  Future<void> _autoFillGps() async {
    if (!mounted || _latCtrl.text.isNotEmpty) return;
    double? lat = ref.read(locationProvider).valueOrNull?.latitude;
    double? lng = ref.read(locationProvider).valueOrNull?.longitude;
    if (lat == null) {
      final cached = ref.read(locationProvider.notifier).cached;
      lat = cached?.latitude;
      lng = cached?.longitude;
    }
    if (lat == null) {
      try {
        final pos = await Geolocator.getLastKnownPosition();
        if (pos != null) { lat = pos.latitude; lng = pos.longitude; }
      } catch (_) {}
    }
    if (lat != null && mounted && _latCtrl.text.isEmpty) {
      setState(() {
        _latCtrl.text = lat!.toStringAsFixed(4);
        _lngCtrl.text = lng!.toStringAsFixed(4);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final voiceState = ref.watch(voiceInputProvider);

    ref.listen(voiceInputProvider, (prev, next) {
      if (next.lastResult != null && next.lastResult != prev?.lastResult) {
        final cur = _textCtrl.text;
        _textCtrl.text = cur.isEmpty ? next.lastResult! : '$cur ${next.lastResult!}';
        _textCtrl.selection = TextSelection.collapsed(offset: _textCtrl.text.length);
        ref.read(voiceInputProvider.notifier).clearResult();
        final autoSave = ref.read(settingsProvider).valueOrNull?.autoSaveVoice ?? false;
        if (autoSave && !_isEditMode) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _save());
        }
      }
    });

    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom + mq.padding.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: math.min(mq.size.height * 0.92, 700)),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 4),
                    _buildTimeRow(),
                    const Divider(height: 16),
                    _buildGpsRow(),
                    const Divider(height: 16),
                    _buildMediaSection(),
                    const Divider(height: 16),
                    _buildFishLengthRow(),
                    const Divider(height: 16),
                    TextField(
                      controller: _textCtrl,
                      autofocus: !widget.startWithVoice &&
                          widget.initialPhotoPath == null &&
                          widget.initialVideoPath == null,
                      maxLines: null,
                      minLines: 3,
                      decoration: InputDecoration(
                        hintText: '메모 내용을 입력하거나 🎤 버튼을 누르세요',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        filled: true,
                        labelText: '📝 메모',
                      ),
                      style: const TextStyle(fontSize: 15, height: 1.4),
                    ),
                    if (voiceState.hasError)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 16),
                          const SizedBox(width: 6),
                          Expanded(child: Text(
                            voiceState.errorMessage ?? '음성을 인식하지 못했습니다',
                            style: const TextStyle(color: Colors.red, fontSize: 13),
                          )),
                          TextButton(
                            onPressed: () => ref.read(voiceInputProvider.notifier).clearError(),
                            child: const Text('다시 시도'),
                          ),
                        ]),
                      ),
                    if (voiceState.isListening && voiceState.interimResult != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          voiceState.interimResult!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              _VoiceButton(voiceState: voiceState, onStart: _startVoice, onStop: _stopVoice),
              const Spacer(),
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('취소'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('저장'),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  // ── 시간 ────────────────────────────────────────────────

  Widget _buildTimeRow() {
    final h = _timestamp.hour.toString().padLeft(2, '0');
    final m = _timestamp.minute.toString().padLeft(2, '0');
    final y = _timestamp.year;
    final mo = _timestamp.month.toString().padLeft(2, '0');
    final d = _timestamp.day.toString().padLeft(2, '0');
    return InkWell(
      onTap: _editTimestamp,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          const Icon(Icons.access_time, size: 18),
          const SizedBox(width: 8),
          Text('⏰ $y-$mo-$d  $h:$m', style: const TextStyle(fontSize: 14)),
          const Spacer(),
          Icon(Icons.edit, size: 15,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
        ]),
      ),
    );
  }

  Future<void> _editTimestamp() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _timestamp,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_timestamp),
    );
    if (time == null || !mounted) return;
    setState(() {
      _timestamp = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  // ── 위경도 ───────────────────────────────────────────────

  Widget _buildGpsRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(Icons.location_on_outlined, size: 16),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
            controller: _latCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: const InputDecoration(
              labelText: '위도',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
            controller: _lngCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: const InputDecoration(
              labelText: '경도',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(width: 4),
        if (_gpsUpdating)
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
        else
          IconButton(
            icon: const Icon(Icons.near_me_outlined, size: 18),
            tooltip: '현재 위치로',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _updateGps,
          ),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          tooltip: 'GPS 삭제',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: () { _latCtrl.clear(); _lngCtrl.clear(); },
        ),
      ],
    );
  }

  Future<void> _updateGps() async {
    setState(() => _gpsUpdating = true);
    try {
      double? lat, lng;
      final cached = ref.read(locationProvider.notifier).cached;
      if (cached?.latitude != null) {
        lat = cached!.latitude; lng = cached.longitude;
      } else {
        final pos = await Geolocator.getLastKnownPosition();
        if (pos != null) { lat = pos.latitude; lng = pos.longitude; }
      }
      if (lat != null && mounted) {
        _latCtrl.text = lat.toString();
        _lngCtrl.text = lng.toString();
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _gpsUpdating = false);
    }
  }

  // ── 미디어 (사진/동영상) ──────────────────────────────────

  Widget _buildMediaSection() {
    final colorScheme = Theme.of(context).colorScheme;
    final savePath = ref.read(settingsProvider).valueOrNull?.savePath ?? '';
    final hasPhoto = _photoPath != null;
    final hasVideo = _videoPath != null;
    final hasMedia = hasPhoto || hasVideo;

    final mediaIcon = hasVideo
        ? Icons.videocam_outlined
        : Icons.photo_camera_outlined;

    return Row(
      crossAxisAlignment: hasMedia ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Padding(
          padding: hasMedia ? const EdgeInsets.only(top: 2) : EdgeInsets.zero,
          child: Icon(mediaIcon, size: 18),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasPhoto) ...[
                SafImage(
                  photoPath: _photoPath!,
                  savePath: savePath,
                  height: (MediaQuery.of(context).size.shortestSide * 0.3).clamp(100.0, 220.0),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _saving ? null : _pickMedia,
                    child: const Text('변경'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.error,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _saving
                        ? null
                        : () => setState(() { _photoPath = null; _videoPath = null; }),
                    child: const Text('삭제'),
                  ),
                ]),
              ] else if (hasVideo) ...[
                VideoPlayerWidget(
                  videoPath: _videoPath!,
                  height: (MediaQuery.of(context).size.shortestSide * 0.3).clamp(100.0, 220.0),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _saving ? null : _pickMedia,
                    child: const Text('변경'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.error,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _saving
                        ? null
                        : () => setState(() { _photoPath = null; _videoPath = null; }),
                    child: const Text('삭제'),
                  ),
                ]),
              ] else
                OutlinedButton(
                  onPressed: _saving ? null : _pickMedia,
                  child: const Text('미디어 추가'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickMedia() async {
    final result = await MemoInputSheet.pickMedia(context, ref);
    if (result == null || !mounted) return;
    setState(() {
      if (result.isVideo) {
        _videoPath = result.path;
        _photoPath = null;
      } else {
        _photoPath = result.path;
        _videoPath = null;
      }
      if (result.length != null && _fishLengthCtrl.text.isEmpty) {
        _fishLengthCtrl.text = result.length!.toStringAsFixed(1);
      }
      if (result.gps != null) {
        _latCtrl.text = result.gps!.lat.toStringAsFixed(4);
        _lngCtrl.text = result.gps!.lng.toStringAsFixed(4);
      }
      if (result.timestamp != null) {
        _timestamp = result.timestamp!;
      }
    });
  }

  // ── 길이 ────────────────────────────────────────────────

  Widget _buildFishLengthRow() {
    return Row(children: [
      const Text('📏', style: TextStyle(fontSize: 16)),
      const SizedBox(width: 8),
      SizedBox(
        width: 110,
        child: TextField(
          controller: _fishLengthCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: '길이 (cm)',
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: OutlineInputBorder(),
          ),
          style: const TextStyle(fontSize: 13),
        ),
      ),
      const SizedBox(width: 4),
      IconButton(
        icon: const Icon(Icons.close, size: 18),
        tooltip: '길이 삭제',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        onPressed: _fishLengthCtrl.clear,
      ),
    ]);
  }

  // ── 음성 ────────────────────────────────────────────────

  Future<void> _startVoice() async {
    final statuses = ref.read(permissionStatusProvider).valueOrNull;
    final micGranted = statuses?[Permission.microphone]?.isGranted ?? false;
    if (!micGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('마이크 권한이 필요합니다. 설정에서 허용해 주세요.')),
      );
      return;
    }
    await ref.read(voiceInputProvider.notifier).startListening();
  }

  Future<void> _stopVoice() async {
    await ref.read(voiceInputProvider.notifier).stopListening();
  }

  // ── 저장 ────────────────────────────────────────────────

  Future<void> _save() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty && _photoPath == null && _videoPath == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    try {
      final latText = _latCtrl.text.trim();
      final lngText = _lngCtrl.text.trim();
      final lat = latText.isEmpty ? null : double.tryParse(latText);
      final lng = lngText.isEmpty ? null : double.tryParse(lngText);
      if ((latText.isNotEmpty && lat == null) || (lngText.isNotEmpty && lng == null)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GPS 좌표 형식이 올바르지 않습니다')),
        );
        setState(() => _saving = false);
        return;
      }
      final fishLengthText = _fishLengthCtrl.text.trim();
      final fishLength = fishLengthText.isEmpty ? null : double.tryParse(fishLengthText);

      final entry = MemoEntry(
        timestamp: _timestamp,
        latitude: lat,
        longitude: lng,
        text: text.isEmpty ? null : text,
        photoPath: _photoPath,
        videoPath: _videoPath,
        fishLength: fishLength,
      );

      if (_isEditMode) {
        if (widget.onEditSave != null) {
          await widget.onEditSave!(widget.blockIndex!, entry);
        } else {
          await ref.read(todayFileProvider.notifier).editBlock(widget.blockIndex!, entry);
        }
      } else {
        if (widget.onAddSave != null) {
          await widget.onAddSave!(entry);
        } else {
          await ref.read(todayFileProvider.notifier).addEntry(entry);
        }
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

}

class _VoiceButton extends StatelessWidget {
  final VoiceInputState voiceState;
  final VoidCallback onStart;
  final VoidCallback onStop;

  const _VoiceButton({required this.voiceState, required this.onStart, required this.onStop});

  @override
  Widget build(BuildContext context) {
    final isListening = voiceState.isListening;
    return GestureDetector(
      onTap: isListening ? onStop : onStart,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 56, height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isListening
              ? Colors.red.withValues(alpha: 0.2)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          border: Border.all(
            color: isListening ? Colors.red : Colors.transparent, width: 2,
          ),
        ),
        child: Icon(
          isListening ? Icons.mic : Icons.mic_none,
          color: isListening ? Colors.red : null,
          size: 28,
        ),
      ),
    );
  }
}
