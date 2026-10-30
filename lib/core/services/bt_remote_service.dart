import 'package:flutter/services.dart';

/// 추임새/삭제 멘트 1개. 텍스트(TTS) 또는 오디오 파일 중 하나.
/// - [type]=='text'면 [value]가 발화 문구, 'audio'면 [value]가 내부 저장 파일명.
/// - [label]은 오디오일 때 표시용 원본 파일명.
class SoundItem {
  final String type; // 'text' | 'audio'
  final String value;
  final String label;
  const SoundItem({required this.type, required this.value, this.label = ''});

  bool get isAudio => type == 'audio';

  factory SoundItem.text(String t) => SoundItem(type: 'text', value: t);
  factory SoundItem.audio(String fileName, String label) =>
      SoundItem(type: 'audio', value: fileName, label: label);

  factory SoundItem.fromMap(Map<dynamic, dynamic> m) => SoundItem(
        type: (m['t'] ?? 'text').toString(),
        value: (m['v'] ?? '').toString(),
        label: (m['label'] ?? '').toString(),
      );

  Map<String, String> toMap() => {'t': type, 'v': value, 'label': label};
}

/// 블루투스 리모컨/이어폰 버튼 → 조과 카운트 액션 매핑의 Flutter 측 래퍼.
/// 매핑 저장소는 네이티브(prefs)이며, 백그라운드 서비스/카운터가 직접 읽는다.
/// action 형식: "add:0"(어종0 +1) / "rem:0"(어종0 −1) / "add:1" / "rem:1".
class BtRemoteService {
  static const _channel = MethodChannel('com.sgchoisg.nakkda/btremote');

  /// 등록(캡처) 중 리모컨 버튼이 눌리면 호출: (keyCode, 미디어키 여부).
  static void Function(int keyCode, bool isMedia)? onKey;

  static bool _handlerSet = false;
  static void _ensureHandler() {
    if (_handlerSet) return;
    _handlerSet = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onRemoteKey') {
        final args = (call.arguments as Map?) ?? const {};
        final kc = args['keyCode'] as int?;
        final media = args['isMedia'] as bool? ?? false;
        if (kc != null) onKey?.call(kc, media);
      }
      return null;
    });
  }

  /// 현재 매핑(action→keyCode).
  static Future<Map<String, int>> getKeyMap() async {
    try {
      final m = await _channel.invokeMapMethod<String, int>('getKeyMap');
      return m ?? {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> setKey(String action, int keyCode) async {
    try {
      await _channel.invokeMethod('setKey', {'action': action, 'keyCode': keyCode});
    } catch (_) {}
  }

  static Future<void> clearKey(String action) async {
    try {
      await _channel.invokeMethod('clearKey', {'action': action});
    } catch (_) {}
  }

  /// 블루투스 버튼 연동 사용 여부(사용자가 켠 경우만 작동). 기본 꺼짐.
  static Future<bool> getEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('getEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod('setEnabled', {'enabled': enabled});
    } catch (_) {}
  }

  /// 볼륨 버튼으로 카운트(원격 볼륨 후킹) 사용 여부. 기본 꺼짐.
  /// 켜면 볼륨 키가 백그라운드·화면꺼짐에서도 ±로 들어오나, 그동안 음악 볼륨 조절은 안 된다.
  static Future<bool> getVolHook() async {
    try {
      return await _channel.invokeMethod<bool>('getVolHook') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setVolHook(bool enabled) async {
    try {
      await _channel.invokeMethod('setVolHook', {'enabled': enabled});
    } catch (_) {}
  }

  /// 조과 효과음(TTS 음성) 사용 여부. 기본 켜짐.
  static Future<bool> getSoundEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('getSoundEnabled') ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setSoundEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod('setSoundEnabled', {'enabled': enabled});
    } catch (_) {}
  }

  /// +1 때 랜덤 재생할 추임새 항목(텍스트·오디오 혼합. 비면 네이티브 기본 세트).
  static Future<List<SoundItem>> getSoundPhrases() async {
    return _getItems('getSoundPhrases');
  }

  static Future<void> setSoundPhrases(List<SoundItem> items) async {
    await _setItems('setSoundPhrases', items);
  }

  /// 삭제(−1) 때 랜덤 재생할 항목(텍스트·오디오 혼합. 비면 네이티브 기본 세트).
  static Future<List<SoundItem>> getSoundDelPhrases() async {
    return _getItems('getSoundDelPhrases');
  }

  static Future<void> setSoundDelPhrases(List<SoundItem> items) async {
    await _setItems('setSoundDelPhrases', items);
  }

  static Future<List<SoundItem>> _getItems(String method) async {
    try {
      final res = await _channel.invokeMethod(method);
      final list = (res as List?) ?? const [];
      return list
          .map((e) => SoundItem.fromMap(e as Map))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _setItems(String method, List<SoundItem> items) async {
    try {
      await _channel.invokeMethod(
          method, {'items': items.map((e) => e.toMap()).toList()});
    } catch (_) {}
  }

  /// 선택한 오디오 파일을 앱 내부 저장소로 복사하고 저장 파일명을 돌려준다(실패 시 null).
  static Future<String?> importSoundFile(String path, String name) async {
    try {
      return await _channel
          .invokeMethod<String>('importSoundFile', {'path': path, 'name': name});
    } catch (_) {
      return null;
    }
  }

  /// 설정 화면 미리듣기 — 저장된 오디오 추임새를 즉시 재생.
  static Future<void> previewAudio(String fileName) async {
    try {
      await _channel.invokeMethod('previewAudio', {'name': fileName});
    } catch (_) {}
  }

  /// 내부 저장 오디오 파일 삭제(항목 제거 시).
  static Future<void> deleteSoundFile(String fileName) async {
    try {
      await _channel.invokeMethod('deleteSoundFile', {'name': fileName});
    } catch (_) {}
  }

  /// 설정 화면 미리듣기 — 지정 문구를 현재 톤·음성으로 즉시 발화.
  static Future<void> previewSound(String text) async {
    try {
      await _channel.invokeMethod('previewSound', {'text': text});
    } catch (_) {}
  }

  /// TTS 톤(pitch)·속도(rate). 기본 각 1.0.
  static Future<({double pitch, double rate})> getSoundTone() async {
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('getSoundTone');
      return (
        pitch: (m?['pitch'] as num?)?.toDouble() ?? 1.0,
        rate: (m?['rate'] as num?)?.toDouble() ?? 1.0,
      );
    } catch (_) {
      return (pitch: 1.0, rate: 1.0);
    }
  }

  static Future<void> setSoundTone(double pitch, double rate) async {
    try {
      await _channel
          .invokeMethod('setSoundTone', {'pitch': pitch, 'rate': rate});
    } catch (_) {}
  }

  /// 엔진이 제공하는 한국어 음성 이름 목록(설치된 것만).
  static Future<List<String>> getSoundVoices() async {
    try {
      final l = await _channel.invokeListMethod<String>('getSoundVoices');
      return l ?? const [];
    } catch (_) {
      return const [];
    }
  }

  /// 선택한 음성 이름(빈 문자열이면 엔진 기본).
  static Future<String> getSoundVoice() async {
    try {
      return await _channel.invokeMethod<String>('getSoundVoice') ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> setSoundVoice(String name) async {
    try {
      await _channel.invokeMethod('setSoundVoice', {'name': name});
    } catch (_) {}
  }

  /// +1 안내 모드: 'phrase'(추임새만) / 'count'(마릿수만) / 'both'(추임새+10단위).
  static Future<String> getSoundMode() async {
    try {
      return await _channel.invokeMethod<String>('getSoundMode') ?? 'both';
    } catch (_) {
      return 'both';
    }
  }

  static Future<void> setSoundMode(String mode) async {
    try {
      await _channel.invokeMethod('setSoundMode', {'mode': mode});
    } catch (_) {}
  }

  /// 카운트 진동 알림 사용 여부(효과음·볼륨과 독립). 기본 꺼짐.
  static Future<bool> getVibrateEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('getVibrateEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setVibrateEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod('setVibrateEnabled', {'enabled': enabled});
    } catch (_) {}
  }

  /// 효과음 관련 설정(멘트·음성·톤·진동·on/off)을 처음 설치 기본값으로 되돌린다.
  static Future<void> resetSound() async {
    try {
      await _channel.invokeMethod('resetSound');
    } catch (_) {}
  }

  /// 등록 모드 시작 — 임시 세션으로 미디어/비미디어 키를 캡처해 [onKey]로 올린다.
  static Future<void> captureStart() async {
    _ensureHandler();
    try {
      await _channel.invokeMethod('captureStart');
    } catch (_) {}
  }

  static Future<void> captureStop() async {
    try {
      await _channel.invokeMethod('captureStop');
    } catch (_) {}
  }
}
