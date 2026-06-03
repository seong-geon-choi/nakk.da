import 'package:flutter_test/flutter_test.dart';
import 'package:vo_rec/features/memo/presentation/voice_input_provider.dart';

void main() {
  group('VoiceInputState', () {
    test('기본값: status=idle, lastResult=null, errorMessage=null', () {
      const state = VoiceInputState();
      expect(state.status, VoiceStatus.idle);
      expect(state.lastResult, isNull);
      expect(state.errorMessage, isNull);
    });

    group('isListening', () {
      test('listening 상태에서 true', () {
        const state = VoiceInputState(status: VoiceStatus.listening);
        expect(state.isListening, isTrue);
      });

      test('idle 상태에서 false', () {
        const state = VoiceInputState(status: VoiceStatus.idle);
        expect(state.isListening, isFalse);
      });

      test('processing 상태에서 false', () {
        const state = VoiceInputState(status: VoiceStatus.processing);
        expect(state.isListening, isFalse);
      });

      test('error 상태에서 false', () {
        const state = VoiceInputState(status: VoiceStatus.error);
        expect(state.isListening, isFalse);
      });
    });

    group('hasError', () {
      test('error 상태에서 true', () {
        const state = VoiceInputState(status: VoiceStatus.error);
        expect(state.hasError, isTrue);
      });

      test('idle 상태에서 false', () {
        const state = VoiceInputState(status: VoiceStatus.idle);
        expect(state.hasError, isFalse);
      });

      test('listening 상태에서 false', () {
        const state = VoiceInputState(status: VoiceStatus.listening);
        expect(state.hasError, isFalse);
      });

      test('processing 상태에서 false', () {
        const state = VoiceInputState(status: VoiceStatus.processing);
        expect(state.hasError, isFalse);
      });
    });

    group('copyWith', () {
      test('status 변경', () {
        const state = VoiceInputState();
        final updated = state.copyWith(status: VoiceStatus.listening);
        expect(updated.status, VoiceStatus.listening);
        expect(updated.lastResult, isNull);
        expect(updated.errorMessage, isNull);
      });

      test('lastResult 변경', () {
        const state = VoiceInputState();
        final updated = state.copyWith(lastResult: '테스트 결과');
        expect(updated.lastResult, '테스트 결과');
        expect(updated.status, VoiceStatus.idle);
        expect(updated.errorMessage, isNull);
      });

      test('errorMessage 변경', () {
        const state = VoiceInputState();
        final updated = state.copyWith(
          status: VoiceStatus.error,
          errorMessage: '오류 발생',
        );
        expect(updated.status, VoiceStatus.error);
        expect(updated.errorMessage, '오류 발생');
        expect(updated.lastResult, isNull);
      });

      test('변경하지 않은 필드는 유지됨', () {
        const state = VoiceInputState(
          status: VoiceStatus.listening,
          lastResult: '기존 결과',
          errorMessage: '기존 오류',
        );
        final updated = state.copyWith(status: VoiceStatus.idle);
        expect(updated.status, VoiceStatus.idle);
        expect(updated.lastResult, '기존 결과');
        expect(updated.errorMessage, '기존 오류');
      });

      test('각 필드 개별 변경 독립성 확인', () {
        const original = VoiceInputState(
          status: VoiceStatus.idle,
          lastResult: null,
          errorMessage: null,
        );
        final withStatus = original.copyWith(status: VoiceStatus.processing);
        final withResult = original.copyWith(lastResult: '결과');
        final withError = original.copyWith(errorMessage: '에러');

        // 원본은 변경되지 않음
        expect(original.status, VoiceStatus.idle);
        expect(original.lastResult, isNull);
        expect(original.errorMessage, isNull);

        // 각 복사본은 해당 필드만 변경됨
        expect(withStatus.status, VoiceStatus.processing);
        expect(withResult.lastResult, '결과');
        expect(withError.errorMessage, '에러');
      });
    });
  });
}
