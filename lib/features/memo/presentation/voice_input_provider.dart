import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

enum VoiceStatus { idle, listening, processing, error }

class VoiceInputState {
  final VoiceStatus status;
  final String? lastResult;
  final String? interimResult;
  final String? errorMessage;

  const VoiceInputState({
    this.status = VoiceStatus.idle,
    this.lastResult,
    this.interimResult,
    this.errorMessage,
  });

  VoiceInputState copyWith({
    VoiceStatus? status,
    String? lastResult,
    String? interimResult,
    bool clearInterim = false,
    String? errorMessage,
  }) =>
      VoiceInputState(
        status: status ?? this.status,
        lastResult: lastResult ?? this.lastResult,
        interimResult: clearInterim ? null : (interimResult ?? this.interimResult),
        errorMessage: errorMessage ?? this.errorMessage,
      );

  bool get isListening => status == VoiceStatus.listening;
  bool get hasError => status == VoiceStatus.error;
}

final voiceInputProvider =
    NotifierProvider<VoiceInputNotifier, VoiceInputState>(
  VoiceInputNotifier.new,
);

class VoiceInputNotifier extends Notifier<VoiceInputState> {
  final SpeechToText _stt = SpeechToText();
  bool _initialized = false;

  @override
  VoiceInputState build() => const VoiceInputState();

  Future<bool> _ensureInitialized() async {
    if (_initialized) return true;
    _initialized = await _stt.initialize(
      onError: (e) {
        state = state.copyWith(
          status: VoiceStatus.error,
          errorMessage: '음성을 인식하지 못했습니다',
        );
      },
    );
    return _initialized;
  }

  Future<void> startListening() async {
    final ok = await _ensureInitialized();
    if (!ok) {
      state = state.copyWith(
        status: VoiceStatus.error,
        errorMessage: '음성 인식을 초기화할 수 없습니다',
      );
      return;
    }
    state = state.copyWith(status: VoiceStatus.listening, errorMessage: null);
    await _stt.listen(
      onResult: (result) {
        if (result.finalResult) {
          state = state.copyWith(
            status: VoiceStatus.idle,
            lastResult: result.recognizedWords,
            clearInterim: true,
          );
        } else {
          state = state.copyWith(interimResult: result.recognizedWords);
        }
      },
      listenOptions: SpeechListenOptions(
        pauseFor: const Duration(seconds: 3),
        localeId: 'ko_KR',
      ),
    );
  }

  Future<void> stopListening() async {
    await _stt.stop();
    state = state.copyWith(status: VoiceStatus.idle, clearInterim: true);
  }

  void clearResult() {
    state = state.copyWith(lastResult: null, errorMessage: null);
  }

  void clearError() {
    state = state.copyWith(
      status: VoiceStatus.idle,
      errorMessage: null,
    );
  }
}
