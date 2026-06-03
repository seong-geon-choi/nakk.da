import 'dart:io';
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
import '../../../features/photo/presentation/photo_provider.dart';

class MemoInputSheet extends ConsumerStatefulWidget {
  final bool startWithVoice;
  final MemoEntry? existingEntry;
  final int? blockIndex;
  final String? initialText;
  final Future<void> Function(int blockIndex, MemoEntry updated)? onEditSave;
  final Future<void> Function(MemoEntry entry)? onAddSave;

  const MemoInputSheet({
    super.key,
    this.startWithVoice = false,
    this.existingEntry,
    this.blockIndex,
    this.initialText,
    this.onEditSave,
    this.onAddSave,
  });

  static Future<void> show(
    BuildContext context, {
    bool voiceMode = false,
    MemoEntry? existingEntry,
    int? blockIndex,
    String? initialText,
    Future<void> Function(int, MemoEntry)? onEditSave,
    Future<void> Function(MemoEntry)? onAddSave,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => MemoInputSheet(
        startWithVoice: voiceMode,
        existingEntry: existingEntry,
        blockIndex: blockIndex,
        initialText: initialText,
        onEditSave: onEditSave,
        onAddSave: onAddSave,
      ),
    );
  }

  @override
  ConsumerState<MemoInputSheet> createState() => _MemoInputSheetState();
}

class _MemoInputSheetState extends ConsumerState<MemoInputSheet> {
  final _controller = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  final _fishLengthController = TextEditingController();
  bool _saving = false;
  bool _gpsUpdating = false;
  // 사진 편집 상태 (isPhoto 수정 모드에서만 사용)
  String? _newPhotoPath;
  bool _photoDeleted = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialText != null) {
      _controller.text = widget.initialText!;
    } else if (widget.existingEntry?.text != null) {
      _controller.text = widget.existingEntry!.text!;
    }
    final lat = widget.existingEntry?.latitude;
    final lng = widget.existingEntry?.longitude;
    if (lat != null) _latController.text = lat.toStringAsFixed(4);
    if (lng != null) _lngController.text = lng.toStringAsFixed(4);
    final fl = widget.existingEntry?.fishLength;
    if (fl != null) _fishLengthController.text = fl.toStringAsFixed(1);
    if (widget.startWithVoice) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startVoice());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _latController.dispose();
    _lngController.dispose();
    _fishLengthController.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final voiceState = ref.watch(voiceInputProvider);

    // 음성 인식 완료 시 텍스트 필드에 삽입 (+ 자동 저장 옵션)
    ref.listen(voiceInputProvider, (prev, next) {
      if (next.lastResult != null && next.lastResult != prev?.lastResult) {
        final cur = _controller.text;
        _controller.text = cur.isEmpty ? next.lastResult! : '$cur ${next.lastResult!}';
        _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
        ref.read(voiceInputProvider.notifier).clearResult();

        // 신규 메모이고 자동 저장 설정이 켜진 경우 바로 저장
        final autoSave = ref.read(settingsProvider).valueOrNull?.autoSaveVoice ?? false;
        if (autoSave && widget.blockIndex == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _save());
        }
      }
    });

    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: mq.viewInsets.bottom + mq.padding.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: mq.size.height * 0.85,
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 드래그 핸들
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // 스크롤 가능한 콘텐츠 영역
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    // 사진 편집 영역 (사진 메모 수정 모드에서만 표시)
                    if (widget.existingEntry?.isPhoto == true) _buildPhotoSection(),
                    // 텍스트 입력
                    TextField(
                      controller: _controller,
                      autofocus: !widget.startWithVoice,
                      maxLines: null,
                      minLines: 5,
                      decoration: InputDecoration(
                        hintText: '메모를 입력하거나 🎤 버튼을 누르세요',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                      ),
                      style: const TextStyle(fontSize: 15, height: 1.4),
                    ),
                    const SizedBox(height: 8),
                    // GPS 행 (수정 모드에서만 표시)
                    if (widget.existingEntry != null) _buildGpsRow(),
                    if (widget.existingEntry != null) const SizedBox(height: 4),
                    if (widget.existingEntry != null) _buildFishLengthRow(),
                    const SizedBox(height: 4),
                    // 에러 메시지
                    if (voiceState.hasError)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                voiceState.errorMessage ?? '음성을 인식하지 못했습니다',
                                style: const TextStyle(color: Colors.red, fontSize: 13),
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  ref.read(voiceInputProvider.notifier).clearError(),
                              child: const Text('다시 시도'),
                            ),
                          ],
                        ),
                      ),
                    // 실시간 음성 미리보기
                    if (voiceState.isListening && voiceState.interimResult != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          voiceState.interimResult!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 버튼 행 (하단 고정)
            Row(
              children: [
                // 음성 버튼
                _VoiceButton(
                  voiceState: voiceState,
                  onStart: _startVoice,
                  onStop: _stopVoice,
                ),
                const Spacer(),
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('취소'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('저장'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoSection() {
    final photoPath = _photoDeleted ? null : (_newPhotoPath ?? widget.existingEntry!.photoPath);
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: photoPath != null && File(photoPath).existsSync()
                ? Image.file(File(photoPath),
                    height: 100, width: double.infinity, fit: BoxFit.cover)
                : Container(
                    height: 60,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        _photoDeleted ? '사진이 삭제됩니다' : '사진을 불러올 수 없음',
                        style: TextStyle(fontSize: 13, color: colorScheme.onSurface.withValues(alpha: 0.5)),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.photo_library_outlined, size: 16),
                label: const Text('사진 변경'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: _saving ? null : _changePicture,
              ),
              const SizedBox(width: 8),
              if (!_photoDeleted)
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('사진 삭제'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.error,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: _saving ? null : () => setState(() => _photoDeleted = true),
                )
              else
                OutlinedButton.icon(
                  icon: const Icon(Icons.undo, size: 16),
                  label: const Text('되돌리기'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => setState(() {
                    _photoDeleted = false;
                    _newPhotoPath = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Future<void> _changePicture() async {
    final source = await showModalBottomSheet<PhotoSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('갤러리에서 선택'),
              onTap: () => Navigator.of(context).pop(PhotoSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final tempPath = await ref.read(photoServiceProvider).pickImage(source: source);
    if (tempPath == null || !mounted) return;

    // 수정 시에는 savePath 디렉토리에만 복사 (갤러리 중복 등록 방지)
    final settings = ref.read(settingsProvider).valueOrNull;
    final savedPath = await _copyToSaveDir(tempPath, settings?.savePath);

    if (mounted) {
      setState(() {
        _newPhotoPath = savedPath ?? tempPath;
        _photoDeleted = false;
      });
    }
  }

  /// savePath 디렉토리의 photos/ 폴더에 파일을 복사해 절대 경로 반환.
  /// 실패 시 null 반환.
  Future<String?> _copyToSaveDir(String srcPath, String? savePath) async {
    if (savePath == null) return null;
    try {
      final src = File(srcPath);
      final ext = srcPath.contains('.') ? srcPath.split('.').last : 'jpg';
      final ts = DateTime.now().millisecondsSinceEpoch;
      final dest = File('$savePath/photos/photo_$ts.$ext');
      await dest.parent.create(recursive: true);
      await src.copy(dest.path);
      return dest.path;
    } catch (_) {
      return null;
    }
  }

  Widget _buildFishLengthRow() {
    return Row(
      children: [
        const Text('📏', style: TextStyle(fontSize: 16)),
        const SizedBox(width: 6),
        SizedBox(
          width: 110,
          child: TextField(
            controller: _fishLengthController,
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
          onPressed: _fishLengthController.clear,
        ),
      ],
    );
  }

  Widget _buildGpsRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(Icons.gps_fixed, size: 16),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
            controller: _latController,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
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
            controller: _lngController,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
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
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          IconButton(
            icon: const Icon(Icons.my_location, size: 18),
            tooltip: '현재 위치로 채우기',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _updateGps,
          ),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          tooltip: 'GPS 삭제',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: () {
            _latController.clear();
            _lngController.clear();
          },
        ),
      ],
    );
  }

  Future<void> _updateGps() async {
    setState(() => _gpsUpdating = true);
    try {
      double? lat, lng;
      final cached = ref.read(locationProvider.notifier).cached;
      if (cached != null && cached.latitude != null) {
        lat = cached.latitude;
        lng = cached.longitude;
      } else {
        final pos = await Geolocator.getLastKnownPosition();
        if (pos != null) {
          lat = pos.latitude;
          lng = pos.longitude;
        }
      }
      if (lat != null && mounted) {
        _latController.text = lat.toString();
        _lngController.text = lng.toString();
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _gpsUpdating = false);
    }
  }

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

  Future<void> _save() async {
    final text = _controller.text.trim();
    final isEditMode = widget.blockIndex != null && widget.existingEntry != null;

    // 신규 입력에서만 빈 텍스트를 취소로 처리
    if (text.isEmpty && !isEditMode) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    try {
      if (isEditMode) {
        // GPS 입력값 검증
        final latText = _latController.text.trim();
        final lngText = _lngController.text.trim();
        final lat = latText.isEmpty ? null : double.tryParse(latText);
        final lng = lngText.isEmpty ? null : double.tryParse(lngText);
        if ((latText.isNotEmpty && lat == null) ||
            (lngText.isNotEmpty && lng == null)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('GPS 좌표 형식이 올바르지 않습니다')),
          );
          setState(() => _saving = false);
          return;
        }
        // 수정 모드: 타임스탬프 유지, 사진은 편집 상태 반영
        final updatedPhoto = _photoDeleted
            ? null
            : (_newPhotoPath ?? widget.existingEntry!.photoPath);
        // 사진도 없고 텍스트도 없으면 저장하지 않고 닫기
        if (updatedPhoto == null && text.isEmpty) {
          Navigator.of(context).pop();
          return;
        }
        final fishLengthText = _fishLengthController.text.trim();
        final fishLength = fishLengthText.isEmpty ? null : double.tryParse(fishLengthText);
        final updated = MemoEntry(
          timestamp: widget.existingEntry!.timestamp,
          latitude: lat,
          longitude: lng,
          text: text.isEmpty ? null : text,
          photoPath: updatedPhoto,
          fishLength: fishLength,
        );
        if (widget.onEditSave != null) {
          await widget.onEditSave!(widget.blockIndex!, updated);
        } else {
          await ref
              .read(todayFileProvider.notifier)
              .editBlock(widget.blockIndex!, updated);
        }
      } else {
        // 신규: cached → lastKnown 순으로 GPS 확보
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
            if (pos != null) {
              lat = pos.latitude;
              lng = pos.longitude;
            }
          } catch (_) {}
        }
        final entry = MemoEntry(
          timestamp: DateTime.now(),
          latitude: lat,
          longitude: lng,
          text: text,
        );
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

  const _VoiceButton({
    required this.voiceState,
    required this.onStart,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final isListening = voiceState.isListening;
    return GestureDetector(
      onTap: isListening ? onStop : onStart,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isListening
              ? Colors.red.withValues(alpha: 0.2)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          border: Border.all(
            color: isListening ? Colors.red : Colors.transparent,
            width: 2,
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
