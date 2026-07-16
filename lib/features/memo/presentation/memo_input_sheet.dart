import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
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
import '../../../features/species_ai/domain/species_prediction.dart';
import '../../../features/species_ai/presentation/species_recognizer_provider.dart';
import '../../../features/species_ai/data/dataset_upload_service.dart';
import '../../../core/widgets/video_player_widget.dart';
import '../../../core/screens/gallery_picker_screen.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/species_detector.dart';

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
  static Future<({String path, bool isVideo, double? length, ({double lat, double lng})? gps, DateTime? timestamp, List<({String path, bool isVideo})>? multi})?> pickMedia(
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
      // AR에서 드래그한 워터마크 위치를 설정에 반영하고 굽기에 사용
      var effectiveWm = wmSettings;
      if (wmSettings != null && arResult.posX != null && arResult.posY != null) {
        effectiveWm = wmSettings.copyWith(
            containerPosX: arResult.posX!, containerPosY: arResult.posY!);
        await ref.read(settingsProvider.notifier).updateWatermark(effectiveWm);
      }
      final needsAddress = effectiveWm != null &&
          effectiveWm.enabled &&
          effectiveWm.boxes.any((b) =>
              b.visible && b.textContent == WatermarkTextContent.address);
      final wmAddress = needsAddress
          ? await ref.read(locationProvider.notifier).resolveWatermarkAddress()
          : null;
      // 세로로 캡처된 AR 사진을 기기 방향(turns)대로 회전(카메라와 동일 규약).
      final rotateDeg = rotateDegreesForTurns(arResult.uiTurns);
      // applyWatermark는 이미지를 rotateDeg로 회전한 '뒤' 굽는데, posX/posY는 세로
      // 프리뷰 좌표계 기준이라 그대로 두면 축이 어긋난다. 저장 회전과 동일한 회전을
      // 위치에도 적용해 프리뷰 위치와 맞춘다(원본 위치는 이미 위에서 설정에 저장됨).
      var bakeWm = effectiveWm;
      if (effectiveWm != null &&
          arResult.posX != null &&
          arResult.posY != null) {
        final px = arResult.posX!, py = arResult.posY!;
        final (double bpx, double bpy) = switch (arResult.uiTurns) {
          1 => (py, 1 - px),
          3 => (1 - py, px),
          _ => (px, py),
        };
        bakeWm = effectiveWm.copyWith(containerPosX: bpx, containerPosY: bpy);
      }
      final rawPath = (arResult.applyWatermark && bakeWm != null)
          ? await applyWatermark(arResult.path, bakeWm.copyWith(enabled: true),
              address: wmAddress, rotateDegrees: rotateDeg)
          : (rotateDeg != 0
              ? await rotateImageFile(arResult.path, rotateDeg)
              : arResult.path);
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
      final picked = await Navigator.of(context).push<Object?>(
        MaterialPageRoute(builder: (_) => const GalleryPickerScreen()),
      );
      if (picked == null || !context.mounted) return null;
      // 멀티 선택 추가: 경로 목록을 그대로 반환(호출부에서 일괄 처리)
      if (picked is List) {
        final items = picked.cast<({String path, bool isVideo})>();
        if (items.isEmpty) return null;
        return (
          path: '', isVideo: false, length: null, gps: null,
          timestamp: null, multi: items,
        );
      }
      final single = picked as ({String path, bool isVideo});
      isVideo = single.isVideo;
      if (isVideo) {
        final savedPath = await MemoInputSheet.copyGalleryVideo(single.path, settings?.savePath ?? '');
        if (savedPath == null) return null;
        path = savedPath;
      } else {
        exifSourcePath = single.path;
        path = single.path; // 원본 경로 직접 참조 (복사 없음)
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
    return (path: path, isVideo: isVideo, length: length, gps: gps, timestamp: timestamp, multi: null);
  }

  /// 갤러리 사진을 savePath의 photos/ 서브폴더에 복사, 상대 경로 반환
  static Future<String?> copyGalleryPhoto(String cachePath, String savePath, {String? filenameOverride}) async {
    // 소스 파일명을 그대로 사용 → 같은 사진은 항상 같은 경로 (중복 복사 방지)
    final srcName = cachePath.split('/').last;
    final filename = filenameOverride ?? srcName;
    if (SafService.isSafUri(savePath)) {
      try {
        await SafService().copyFileToSafFolder(cachePath, savePath, filename);
        return 'photos/$filename';
      } catch (_) { return null; }
    } else if (savePath.isNotEmpty) {
      try {
        final photosDir = Directory('$savePath/photos');
        await photosDir.create(recursive: true);
        final destFile = File('${photosDir.path}/$filename');
        if (!await destFile.exists()) {
          await File(cachePath).copy(destFile.path);
        }
        return 'photos/$filename';
      } catch (_) { return null; }
    }
    return null;
  }

  static Future<String?> copyGalleryVideo(String tempPath, String savePath) {
    // 갤러리에서 가져온 동영상(content URI)은 복사 없이 원본 참조
    if (tempPath.startsWith('content://')) return Future.value(tempPath);
    return saveToGallery(tempPath, relativePath: 'DCIM/nakkda');
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
  final _fishSpeciesCtrl = TextEditingController();
  late DateTime _timestamp;
  String? _photoPath;
  String? _videoPath;
  bool _saving = false;
  bool _gpsUpdating = false;
  List<SpeciesPrediction> _speciesCandidates = const [];
  bool _recognizing = false;
  // 최상위 후보가 이 확률 미만이면 '인식 불확실'로 표시
  static const double _kConfidentThreshold = 0.5;

  bool get _isEditMode => widget.blockIndex != null && widget.existingEntry != null;

  /// 수정 중인 기존 메모에 어종/길이가 이미 들어 있는지
  bool get _existingHasCatch {
    final e = widget.existingEntry;
    if (e == null) return false;
    return (e.fishSpecies != null && e.fishSpecies!.trim().isNotEmpty) ||
        e.fishLength != null;
  }

  /// 조과 입력을 다룰지: 설정이 켜져 있거나, 수정 중인 메모에 이미 조과 정보가 있을 때.
  /// (설정이 꺼져 있어도 기존 조과 메모는 수정 화면에서 보고 편집할 수 있게 함)
  bool get _catchEnabled =>
      (ref.read(settingsProvider).valueOrNull?.showCatchInput ?? true) ||
      _existingHasCatch;

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(_autoDetectFromText);
    final entry = widget.existingEntry;
    if (entry != null) {
      _timestamp = entry.timestamp;
      _photoPath = entry.photoPath;
      _videoPath = entry.videoPath;
      _textCtrl.text = entry.text ?? '';
      if (entry.latitude != null) _latCtrl.text = entry.latitude!.toStringAsFixed(4);
      if (entry.longitude != null) _lngCtrl.text = entry.longitude!.toStringAsFixed(4);
      if (entry.fishLength != null) _fishLengthCtrl.text = entry.fishLength!.toStringAsFixed(1);
      if (entry.fishSpecies != null) _fishSpeciesCtrl.text = entry.fishSpecies!;
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
    // 진입 시 이미 사진이 있으면(홈에서 첨부·기존 메모 편집) 어종 추천 실행
    if (_photoPath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _recognizePhoto());
    }
  }

  /// SAF(content://) 또는 로컬 경로의 사진 바이트를 읽는다. (SafImage 로직과 동일)
  Future<Uint8List?> _readPhotoBytes(String photoPath, String savePath) async {
    final effective = (SafImage.isAbsolute(photoPath) && !File(photoPath).existsSync())
        ? 'photos/${photoPath.split('/').last}'
        : photoPath;
    if (!SafImage.isAbsolute(effective) && SafService.isSafUri(savePath)) {
      return SafService().readSafImage(savePath, effective);
    }
    final resolved =
        SafImage.isAbsolute(effective) ? effective : '$savePath/$effective';
    final f = File(resolved);
    return await f.exists() ? f.readAsBytes() : null;
  }

  /// 현재 사진에서 어종 후보(상위 3개)를 추론해 칩으로 표시.
  /// AI 학습용 사진 제공(contributeImages)에 동의한 사용자만 사용 가능.
  Future<void> _recognizePhoto() async {
    final path = _photoPath;
    if (path == null) return;
    final contributeImages =
        ref.read(settingsProvider).valueOrNull?.contributeImages ?? false;
    if (!contributeImages) return;
    final rec = await ref.read(speciesRecognizerProvider.future);
    if (rec == null || !mounted || _photoPath != path) return; // 모델 없거나 그새 사진 변경
    setState(() => _recognizing = true);
    final savePath = ref.read(settingsProvider).valueOrNull?.savePath ?? '';
    try {
      final bytes = await _readPhotoBytes(path, savePath);
      if (bytes != null && mounted && _photoPath == path) {
        final result = await rec.classifyBytes(bytes);
        if (mounted && _photoPath == path) {
          setState(() {
            _speciesCandidates = result;
            _recognizing = false;
          });
          return;
        }
      }
    } catch (_) {}
    if (mounted && _photoPath == path) setState(() => _recognizing = false);
  }

  /// 메모 텍스트에서 어종·길이를 인식해 필드에 반영한다.
  /// - 작성(추가): 필드가 비어 있을 때만 채움 (AR 측정 길이 등 보존)
  /// - 수정: 이미 값이 있어도 메모 내용에서 인식되면 그 값으로 업데이트
  void _autoDetectFromText() {
    // 조과 입력을 다루지 않는 경우(섹션 숨김) 자동 인식하지 않음
    if (!_catchEnabled) return;
    final text = _textCtrl.text;
    final overwrite = _isEditMode;
    String? species;
    double? length;
    if (overwrite || _fishSpeciesCtrl.text.trim().isEmpty) {
      final list =
          ref.read(settingsProvider).valueOrNull?.fishSpecies ?? kCommonFishSpecies;
      species = detectFishSpecies(text, list);
    }
    if (overwrite || _fishLengthCtrl.text.trim().isEmpty) {
      length = detectFishLength(text);
    }
    if (!mounted) return;
    // 인식된 값이 있고 현재 값과 다를 때만 갱신 (텍스트에 없으면 기존 값 유지)
    final newSpecies =
        (species != null && species != _fishSpeciesCtrl.text) ? species : null;
    final lengthStr = length?.toStringAsFixed(1);
    final newLength =
        (lengthStr != null && lengthStr != _fishLengthCtrl.text) ? lengthStr : null;
    if (newSpecies != null || newLength != null) {
      setState(() {
        if (newSpecies != null) _fishSpeciesCtrl.text = newSpecies;
        if (newLength != null) _fishLengthCtrl.text = newLength;
      });
    }
  }

  @override
  void dispose() {
    _textCtrl.removeListener(_autoDetectFromText);
    _textCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _fishLengthCtrl.dispose();
    _fishSpeciesCtrl.dispose();
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
                    if ((ref.watch(settingsProvider).valueOrNull?.showCatchInput ??
                            true) ||
                        _existingHasCatch) ...[
                      _buildCatchSection(),
                      const Divider(height: 16),
                    ],
                    _buildMediaSection(),
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
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    children: [
                      SafImage(
                        photoPath: _photoPath!,
                        savePath: savePath,
                        height: (MediaQuery.of(context).size.shortestSide * 0.3).clamp(100.0, 220.0),
                      ),
                      if (_recognizing || _speciesCandidates.isNotEmpty)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: _buildPhotoOverlay(),
                        ),
                    ],
                  ),
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
    // 편집 시트 안에서는 단일 사진만 다룸 — 멀티 선택은 첫 장만 사용
    final multi = result.multi;
    if (multi != null) {
      if (multi.isEmpty) return;
      final first = multi.first;
      setState(() {
        _speciesCandidates = const [];
        if (first.isVideo) {
          _videoPath = first.path;
          _photoPath = null;
        } else {
          _photoPath = first.path;
          _videoPath = null;
        }
      });
      if (!first.isVideo) _recognizePhoto();
      return;
    }
    setState(() {
      _speciesCandidates = const [];
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
    if (!result.isVideo && _photoPath != null) _recognizePhoto();
  }

  // ── 조과 (어종/길이) ─────────────────────────────────────

  Widget _buildCatchSection() {
    // 드롭다운은 '표시여부' 체크된 어종만 노출 (탐지는 전체 목록 사용)
    final speciesList = [
      ...(ref.watch(settingsProvider).valueOrNull?.visibleFishSpecies ??
          kCommonFishSpecies)
    ]..sort(); // 가나다순 정렬
    // 어종(자유 입력 + 드롭다운)과 길이를 한 줄에 배치
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text('🐟', style: TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _fishSpeciesCtrl,
            decoration: const InputDecoration(
              labelText: '어종',
              hintText: '입력 또는 ▼',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.arrow_drop_down, size: 24),
          tooltip: '어종 선택',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onSelected: (v) => setState(() => _fishSpeciesCtrl.text = v),
          itemBuilder: (_) => speciesList
              .map((s) => PopupMenuItem<String>(value: s, child: Text(s)))
              .toList(),
        ),
        const SizedBox(width: 4),
        const Text('📏', style: TextStyle(fontSize: 16)),
        const SizedBox(width: 6),
        SizedBox(
          width: 96,
          child: TextField(
            controller: _fishLengthCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '길이(cm)',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }

  /// 사진 위에 오버레이할 어종 추론 결과. 탭하면 어종 필드에 채운다.
  /// 확신도가 낮으면(최상위 < 임계값) '인식 불확실' 문구를 표시한다.
  Widget _buildPhotoOverlay() {
    final uncertain = _speciesCandidates.isNotEmpty &&
        _speciesCandidates.first.confidence < _kConfidentThreshold;
    // 관련 항목(헤더+후보 칩)을 한 줄에 배치. 넘치면 가로 스크롤(줄바꿈 없음).
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: Colors.black.withValues(alpha: 0.6), // 사진 밝기와 무관하게 일정한 대비
      child: _recognizing
          ? const Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white)),
              SizedBox(width: 8),
              Text('어종 인식 중…',
                  style: TextStyle(color: Colors.white, fontSize: 12)),
            ])
          : Row(
              children: [
                Text(uncertain ? '❓ 불확실' : '🤖 추천',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (int i = 0; i < _speciesCandidates.length; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          _speciesChip(_speciesCandidates[i]),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _speciesChip(SpeciesPrediction p) {
    return ActionChip(
      label: Text('${p.species} ${p.percent}%'),
      labelStyle: const TextStyle(
          fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w600),
      backgroundColor: Colors.white,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      onPressed: () => setState(() => _fishSpeciesCtrl.text = p.species),
    );
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
    final showCatch = _catchEnabled;
    final hasCatchInfo = showCatch &&
        (_fishSpeciesCtrl.text.trim().isNotEmpty ||
            _fishLengthCtrl.text.trim().isNotEmpty);
    if (text.isEmpty && _photoPath == null && _videoPath == null && !hasCatchInfo) {
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
      double? fishLength;
      String? fishSpecies;
      if (showCatch) {
        final fishLengthText = _fishLengthCtrl.text.trim();
        // 길이가 비어 있으면 메모 텍스트에서 자동 탐지
        fishLength = fishLengthText.isEmpty
            ? detectFishLength(text)
            : double.tryParse(fishLengthText);
        final speciesList =
            ref.read(settingsProvider).valueOrNull?.fishSpecies ?? kCommonFishSpecies;
        final speciesText = _fishSpeciesCtrl.text.trim();
        // 어종이 비어 있으면 메모 텍스트에서 자동 탐지
        fishSpecies =
            speciesText.isEmpty ? detectFishSpecies(text, speciesList) : speciesText;
        // 직접 입력한 새 어종은 목록에 자동 추가 (중복은 무시됨)
        if (fishSpecies != null && fishSpecies.isNotEmpty) {
          await ref.read(settingsProvider.notifier).addFishSpecies(fishSpecies);
        }
      }

      final entry = MemoEntry(
        timestamp: _timestamp,
        latitude: lat,
        longitude: lng,
        text: text.isEmpty ? null : text,
        photoPath: _photoPath,
        videoPath: _videoPath,
        fishLength: fishLength,
        fishSpecies: fishSpecies,
      );

      // 콜백 미지정 시 오늘 파일에 기록(통합 화면은 항상 콜백을 넘김)
      final savePath = ref.read(settingsProvider).valueOrNull?.savePath ?? '';
      final todayPath = todayMemoFilePath(savePath);
      if (_isEditMode) {
        if (widget.onEditSave != null) {
          await widget.onEditSave!(widget.blockIndex!, entry);
        } else {
          await ref.read(dayFileProvider(todayPath).notifier)
              .editBlock(widget.blockIndex!, entry);
        }
      } else {
        if (widget.onAddSave != null) {
          await widget.onAddSave!(entry);
        } else {
          await ref.read(dayFileProvider(todayPath).notifier).addEntry(entry);
        }
      }
      // AI 학습 데이터 기여(옵트인): 사용자가 확정한 {사진, 어종}을 업로드
      final contribute =
          ref.read(settingsProvider).valueOrNull?.contributeImages ?? false;
      if (contribute &&
          _photoPath != null &&
          fishSpecies != null &&
          fishSpecies.isNotEmpty) {
        unawaited(_uploadContribution(_photoPath!, fishSpecies, savePath));
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

  /// 확정된 사진을 학습 데이터로 업로드(옵트인·백그라운드). AI 추천과 일치하면 신뢰도 첨부.
  Future<void> _uploadContribution(
      String photoPath, String species, String savePath) async {
    double? aiConf;
    for (final c in _speciesCandidates) {
      if (c.species == species) {
        aiConf = c.confidence;
        break;
      }
    }
    try {
      final bytes = await _readPhotoBytes(photoPath, savePath);
      if (bytes == null) return;
      await DatasetUploadService().upload(
        photoBytes: bytes,
        species: species,
        dedupKey: photoPath,
        aiConfidence: aiConf,
      );
    } catch (_) {}
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
